-- {"query": "4587.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1634}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestPostEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId,
      rpe.PostHistoryTypeId,
      rpe.CreationDate
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
  ),
  UserEditCounts AS (
    SELECT
      UserId,
      COUNT(DISTINCT PostId) AS DistinctEditedPosts
    FROM LatestPostEdits
    GROUP BY UserId
  ),
  PostEditFrequency AS (
    SELECT
      pe.PostId,
      COUNT(pe.PostHistoryTypeId) AS EditCount,
      MAX(pe.CreationDate) AS LastEditTimestamp
    FROM PostHistory pe
    WHERE pe.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY pe.PostId
  ),
  QuestionAnswerRatios AS (
    SELECT
      p.Id AS QuestionId,
      CAST(COUNT(CASE WHEN p_ans.PostTypeId = 2 THEN 1 END) AS DECIMAL) / NULLIF(COUNT(p.Id), 0) AS AnswerRatio
    FROM Posts p
    LEFT JOIN Posts p_ans
      ON p.Id = p_ans.ParentId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
    HAVING COUNT(p.Id) > 0
  )
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  COALESCE(pr.AnswerRatio, 0) AS QuestionAnswerRatio,
  COALESCE(uec.DistinctEditedPosts, 0) AS UserDistinctEditedPosts,
  COALESCE(p_edit_freq.EditCount, 0) AS PostEditFrequency,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN p.OwnerUserId IS NULL THEN 'Deleted Owner'
    WHEN p.OwnerDisplayName IS NULL THEN 'Unknown Owner'
    ELSE 'Known Owner'
  END AS OwnerStatus,
  CAST((CAST(COALESCE(p.ClosedDate, p.LastActivityDate, p.LastEditDate, p.CreationDate) AS TIMESTAMP) - CAST(p.CreationDate AS TIMESTAMP)) AS INTERVAL) AS PostAgeInterval,
  FLOOR(EXTRACT(EPOCH FROM (CAST(COALESCE(p.ClosedDate, p.LastActivityDate, p.LastEditDate, p.CreationDate) AS TIMESTAMP) - CAST(p.CreationDate AS TIMESTAMP))) / 86400) AS PostAgeInDays,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE c.PostId = p.Id AND c.Score > 5
  ) AS HighScoringCommentCount,
  LEAST(
    COALESCE(p.AnswerCount, 0),
    COALESCE(p.CommentCount, 0)
  ) AS MinAnswerOrComment,
  CASE WHEN p.Tags LIKE '%<sql>%' THEN 'Contains SQL Tag' ELSE 'Does not contain SQL Tag' END AS ContainsSQLTag
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserEditCounts uec
  ON p.OwnerUserId = uec.UserId
LEFT JOIN PostEditFrequency p_edit_freq
  ON p.Id = p_edit_freq.PostId
LEFT JOIN QuestionAnswerRatios pr
  ON p.Id = pr.QuestionId
WHERE
  p.Score > 10
  AND p.ViewCount > 1000
  AND p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND EXISTS (
    SELECT 1
    FROM PostLinks pl
    WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
  )
UNION ALL
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  COALESCE(pr.AnswerRatio, 0) AS QuestionAnswerRatio,
  COALESCE(uec.DistinctEditedPosts, 0) AS UserDistinctEditedPosts,
  COALESCE(p_edit_freq.EditCount, 0) AS PostEditFrequency,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN p.OwnerUserId IS NULL THEN 'Deleted Owner'
    WHEN p.OwnerDisplayName IS NULL THEN 'Unknown Owner'
    ELSE 'Known Owner'
  END AS OwnerStatus,
  CAST((CAST(COALESCE(p.ClosedDate, p.LastActivityDate, p.LastEditDate, p.CreationDate) AS TIMESTAMP) - CAST(p.CreationDate AS TIMESTAMP)) AS INTERVAL) AS PostAgeInterval,
  FLOOR(EXTRACT(EPOCH FROM (CAST(COALESCE(p.ClosedDate, p.LastActivityDate, p.LastEditDate, p.CreationDate) AS TIMESTAMP) - CAST(p.CreationDate AS TIMESTAMP))) / 86400) AS PostAgeInDays,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE c.PostId = p.Id AND c.Score > 5
  ) AS HighScoringCommentCount,
  LEAST(
    COALESCE(p.AnswerCount, 0),
    COALESCE(p.CommentCount, 0)
  ) AS MinAnswerOrComment,
  CASE WHEN p.Tags LIKE '%<sql>%' THEN 'Contains SQL Tag' ELSE 'Does not contain SQL Tag' END AS ContainsSQLTag
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserEditCounts uec
  ON p.OwnerUserId = uec.UserId
LEFT JOIN PostEditFrequency p_edit_freq
  ON p.Id = p_edit_freq.PostId
LEFT JOIN QuestionAnswerRatios pr
  ON p.Id = pr.QuestionId
WHERE
  p.Score < -5
  AND p.CreationDate < DATE '2022-01-01'
  AND NOT EXISTS (
    SELECT 1
    FROM PostLinks pl
    WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
  );