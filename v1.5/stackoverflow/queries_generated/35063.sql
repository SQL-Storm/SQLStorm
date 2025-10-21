-- {"query": "35063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 979} 
WITH TopUsersByReputation AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > (
        SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY Reputation) FROM Users
    )
),
QuestionsWithMostActivity AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COUNT(DISTINCT c.Id) AS NumComments,
        COUNT(DISTINCT a.Id) AS NumAnswers,
        COALESCE(SUM(v.Score),0) AS TotalCommentScore
    FROM
        Posts p
        LEFT JOIN Comments c ON c.PostId = p.Id
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
        LEFT JOIN Comments v ON v.PostId = p.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= NOW() - INTERVAL '180 days'
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount
    HAVING
        COUNT(DISTINCT a.Id) > 2
        AND COUNT(DISTINCT c.Id) > 4
),
MostAwardedUsersOnActiveQuestions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        array_agg(DISTINCT b.Name) FILTER (WHERE b.Class = 1) AS GoldBadges
    FROM
        TopUsersByReputation u
        INNER JOIN QuestionsWithMostActivity q ON u.Id = q.OwnerUserId
        LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(b.Id) > 5
),
PopularTagsLastQuarter AS (
    SELECT
        t.TagName,
        SUM(t.Count) AS TagCount
    FROM
        Tags t
        INNER JOIN Posts p ON (
            (p.Tags LIKE '%' || '<' || t.TagName || '>' || '%')
            AND p.CreationDate >= (date_trunc('quarter', NOW()) - INTERVAL '1 quarter')
            AND p.CreationDate < date_trunc('quarter', NOW())
            AND p.PostTypeId = 1
        )
    GROUP BY
        t.TagName
    HAVING
        SUM(t.Count) > 500
),
HotQuestionsWithDupesAndVotes AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT pl.Id) AS DuplicateLinks
    FROM
        Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= NOW() - INTERVAL '90 days'
    GROUP BY
        p.Id, p.Title, p.Tags
    HAVING
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 10
        AND COUNT(DISTINCT pl.Id) > 0
)
SELECT
    u.UserId,
    u.DisplayName,
    u.BadgeCount,
    u.GoldBadges,
    q.QuestionId,
    q.Title AS QuestionTitle,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    pt.TagName AS ActiveTag,
    hq.UpVotes,
    hq.DownVotes,
    hq.DuplicateLinks
FROM
    MostAwardedUsersOnActiveQuestions u
    INNER JOIN QuestionsWithMostActivity q ON u.UserId = q.OwnerUserId
    LEFT JOIN PopularTagsLastQuarter pt
        ON q.Tags LIKE '%' || '<' || pt.TagName || '>' || '%'
    LEFT JOIN HotQuestionsWithDupesAndVotes hq
        ON q.QuestionId = hq.QuestionId
ORDER BY
    u.BadgeCount DESC,
    q.ViewCount DESC,
    hq.UpVotes DESC NULLS LAST,
    q.CreationDate DESC
LIMIT 100;