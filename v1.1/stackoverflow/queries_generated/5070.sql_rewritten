-- {"query": "5070.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1067} 
WITH TopTagUsers AS (
    SELECT
        t.TagName,
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(COALESCE(p.Score, 0)) DESC, COUNT(*) DESC) AS TagUserRank
    FROM Tags t
    JOIN Posts p ON p.Tags IS NOT NULL
        AND POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
        AND p.OwnerUserId IS NOT NULL
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count >= 1000
    GROUP BY t.TagName, u.Id, u.DisplayName
),
ActiveHighRepUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCountLastYear
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
DuplicateQuestionPairs AS (
    SELECT
        pl.PostId AS OriginalPostId,
        pl.RelatedPostId AS DuplicatePostId,
        pl.CreationDate,
        p1.OwnerUserId AS OriginalOwnerId,
        p2.OwnerUserId AS DuplicateOwnerId
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id AND lt.Name = 'Duplicate'
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE p1.PostTypeId = 1 AND p2.PostTypeId = 1
),
EditsWithComments AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount,
        SUM(CASE WHEN ph.Comment IS NOT NULL AND TRIM(ph.Comment) <> '' THEN 1 ELSE 0 END) AS CommentedEditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,24) -- Edit Title/Body/Tags or Suggested Edit Applied
    GROUP BY ph.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ttu.TagName, '[No Tag]') AS TopTag,
    ttu.QuestionCount,
    ttu.AnswerCount,
    ttu.TotalPostScore,
    ttu.TagUserRank,
    ahru.PostCountLastYear,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    sq1.DuplicatePostsAuthored,
    sq2.QuestionsWithCommentedEdits,
    sq3.AvgEditCommentLength
FROM Users u
LEFT JOIN (
    SELECT DISTINCT ON (TagName, UserId) TagName, UserId, QuestionCount, AnswerCount, TotalPostScore, TagUserRank
    FROM TopTagUsers
    WHERE TagUserRank <= 3
) ttu ON u.Id = ttu.UserId
LEFT JOIN ActiveHighRepUsers ahru ON u.Id = ahru.Id
LEFT JOIN LATERAL (
    SELECT COUNT(DISTINCT dqp.DuplicatePostId) AS DuplicatePostsAuthored
    FROM DuplicateQuestionPairs dqp
    WHERE dqp.DuplicateOwnerId = u.Id
) sq1 ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(p.Id) AS QuestionsWithCommentedEdits
    FROM Posts p
    JOIN EditsWithComments ewc ON ewc.PostId = p.Id
    WHERE p.OwnerUserId = u.Id
      AND p.PostTypeId = 1
      AND ewc.CommentedEditCount > 0
) sq2 ON TRUE
LEFT JOIN LATERAL (
    SELECT AVG(LENGTH(ph.Comment)) AS AvgEditCommentLength
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE p.OwnerUserId = u.Id
      AND ph.Comment IS NOT NULL AND TRIM(ph.Comment) <> ''
      AND ph.PostHistoryTypeId IN (4,5,6,24)
) sq3 ON TRUE
WHERE u.Reputation > 5000 OR ttu.UserId IS NOT NULL OR ahru.Id IS NOT NULL
ORDER BY
    COALESCE(ahru.PostCountLastYear, 0) DESC,
    COALESCE(ttu.TotalPostScore, 0) DESC,
    u.Reputation DESC
LIMIT 100;