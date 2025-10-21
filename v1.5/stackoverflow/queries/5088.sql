WITH
TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        RANK() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) as UserRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
QuestionEngagement AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        (SELECT COUNT(1) FROM Posts a WHERE a.ParentId = p.Id) AS AnswerCount,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
        MAX(a.CreationDate) AS LatestAnswerDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '2 years'
    GROUP BY p.Id, p.Title, p.Tags, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        p1.Title AS PostTitle,
        p2.Title AS RelatedPostTitle,
        pl.CreationDate AS LinkCreationDate
    FROM PostLinks pl
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE pl.LinkTypeId = 3
),
TagStats AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithTag,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersWithTag
    FROM Tags t
    LEFT JOIN Posts p
        ON (p.Tags IS NOT NULL AND POSITION('|'||t.TagName||'|' IN REPLACE(REPLACE(p.Tags, '><', '|'), '<','|')) > 0)
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 20
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.BadgeCount,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.UserRank,
    q.QuestionId,
    COALESCE(q.Title, '[no title]') AS QuestionTitle,
    q.Tags,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.UpVoteCount,
    q.DownVoteCount,
    d.RelatedPostId AS DuplicateOf,
    d.RelatedPostTitle AS DuplicateTitle,
    EXTRACT(EPOCH FROM (COALESCE(q.LatestAnswerDate, q.CreationDate) - q.CreationDate))/3600.0 AS HoursToLatestAnswer,
    ts.TagName,
    ts.TagPostCount,
    ts.QuestionsWithTag,
    ts.AnswersWithTag
FROM TopUsers tu
LEFT JOIN QuestionEngagement q ON q.OwnerUserId = tu.UserId
LEFT JOIN LATERAL (
    SELECT d2.*
    FROM DuplicateLinks d2
    WHERE d2.PostId = q.QuestionId
    ORDER BY d2.LinkCreationDate DESC
    LIMIT 1
) d ON TRUE
LEFT JOIN LATERAL (
    SELECT ts2.*
    FROM TagStats ts2
    WHERE POSITION('|'||ts2.TagName||'|' IN REPLACE(REPLACE(COALESCE(q.Tags,''), '><', '|'), '<','|')) > 0
    ORDER BY ts2.TagPostCount DESC
    LIMIT 1
) ts ON TRUE
WHERE
    tu.UserRank <= 50
    AND (
        q.UpVoteCount IS NULL OR
        (CAST(q.UpVoteCount AS float) / NULLIF(q.DownVoteCount,0)) > 2
        OR q.DownVoteCount IS NULL
    )
    AND (
        q.AnswerCount IS NULL OR q.AnswerCount >= 1
    )
    AND (
        ts.TagName IS NULL OR ts.TagPostCount > 100
    )
ORDER BY
    tu.UserRank,
    q.Score DESC NULLS LAST,
    q.CreationDate DESC
LIMIT 200;