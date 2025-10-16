-- {"query": "3074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1183} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRank
    FROM
        Posts p
),
RecentOpenQuestions AS (
    SELECT
        rp.Id AS QuestionId,
        rp.Title,
        rp.CreationDate AS QuestionCreationDate,
        rp.LastActivityDate,
        rp.OwnerUserId,
        u.Reputation,
        u.Location,
        u.AboutMe
    FROM
        RankedPosts rp
    LEFT OUTER JOIN
        Users u ON rp.OwnerUserId = u.Id
    WHERE
        rp.PostTypeId = 1
        AND rp.PostRank = 1
        AND rp.ClosedDate IS NULL
        AND rp.LastActivityDate > (CURRENT_TIMESTAMP - INTERVAL '30 days')
),
TopAnswerers AS (
    SELECT
        a.OwnerUserId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
    GROUP BY
        a.OwnerUserId
),
AnswererInfo AS (
    SELECT
        ta.OwnerUserId,
        ta.AnswerCount,
        ta.AvgAnswerScore,
        u.DisplayName,
        u.Reputation AS UserReputation,
        u.Location,
        u.AboutMe,
        CASE WHEN u.Reputation >= 2000 THEN 'Power User'
             WHEN u.Reputation BETWEEN 1000 AND 1999 THEN 'Intermediate'
             ELSE 'Beginner' END AS UserLevel
    FROM
        TopAnswerers ta
    LEFT JOIN
        Users u ON ta.OwnerUserId = u.Id
),
QuestionVoteAgg AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 10 THEN 1 END) AS CloseVotes,
        COUNT(CASE WHEN v.VoteTypeId = 12 THEN 1 END) AS SpamVotes
    FROM
        Posts q
    LEFT OUTER JOIN
        Votes v ON q.Id = v.PostId
    WHERE
        q.PostTypeId = 1
    GROUP BY
        q.Id
),
TagsInfo AS (
    SELECT
        t.TagName,
        t.Count,
        p.Id AS TagPostId,
        p.Body,
        p.OwnerUserId,
        p.CreationDate
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.WikiPostId = p.Id
),
ImportantTags AS (
    SELECT
        TagName,
        Count,
        Body,
        OwnerUserId,
        CreationDate
    FROM
        TagsInfo
    WHERE
        Count >= (SELECT AVG(Count) FROM Tags)
)
SELECT
    roq.QuestionId,
    roq.Title,
    roq.QuestionCreationDate,
    roq.LastActivityDate,
    roq.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.Location,
    u.AboutMe,
    CASE WHEN u.Reputation >= 2000 THEN 'Power User'
         WHEN u.Reputation BETWEEN 1000 AND 1999 THEN 'Intermediate'
         ELSE 'Beginner' END AS UserLevel,
    COALESCE(qa.AnswerCount,0) AS AnswerCount,
    COALESCE(qa.AvgAnswerScore,0) AS AvgAnswerScore,
    qa.AnswererDisplayName,
    qa.UserReputation,
    qa.UserLevel,
    qva.UpVotes,
    qva.DownVotes,
    qva.CloseVotes,
    qva.SpamVotes,
    ARRAY_AGG(t.TagName) AS Tags,
    ARRAY_AGG(t.Count) AS TagCounts,
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'Tag', t.TagName,
            'Excerpt', p.Body,
            'Owner', p.OwnerDisplayName,
            'Created', p.CreationDate
        )
    ) FILTER (WHERE t.TagName IS NOT NULL) AS TagDetails
FROM
    RecentOpenQuestions roq
LEFT OUTER JOIN
    Users u ON roq.OwnerUserId = u.Id
LEFT OUTER JOIN
    AnswererInfo qa ON roq.OwnerUserId = qa.OwnerUserId
LEFT OUTER JOIN
    QuestionVoteAgg qva ON roq.QuestionId = qva.QuestionId
LEFT OUTER JOIN
    Tags t ON ',' || roq.Tags || ',' LIKE '%,' || t.TagName || ',%'
LEFT OUTER JOIN
    Posts p ON t.WikiPostId = p.Id
GROUP BY
    roq.QuestionId,
    roq.Title,
    roq.QuestionCreationDate,
    roq.LastActivityDate,
    roq.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.AboutMe,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qa.OwnerDisplayName,
    qa.UserReputation,
    qa.UserLevel,
    qva.UpVotes,
    qva.DownVotes,
    qva.CloseVotes,
    qva.SpamVotes
HAVING
    COUNT(t.TagName) > 0
ORDER BY
    roq.LastActivityDate DESC
LIMIT 100;