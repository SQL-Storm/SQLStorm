-- {"query": "4057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1398}
WITH
  LatestPostEdit AS (
    SELECT
      ph.PostId,
      ph.UserId AS LastEditorUserId,
      u.DisplayName AS LastEditorDisplayName,
      ph.CreationDate AS LastEditDate,
      ROW_NUMBER() OVER (
        PARTITION BY ph.PostId
        ORDER BY ph.CreationDate DESC
      ) AS rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 7, 8)
  ),
  TopAnswers AS (
    SELECT
      p.Id AS QuestionId,
      p.AcceptedAnswerId,
      p.ParentId,
      p.Id AS AnswerId,
      p.OwnerUserId,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (
        PARTITION BY p.ParentId
        ORDER BY p.Score DESC
      ) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2
  ),
  AvgCommentScore AS (
    SELECT
      c.PostId,
      AVG(c.Score) AS AvgScore
    FROM Comments c
    GROUP BY c.PostId
  ),
  ExperiencedQuestioners AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
    HAVING
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) >= 1
      AND COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) > 10
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  CASE
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Active'
  END AS PostStatus,
  (COALESCE(p.AnswerCount, 0) || ' answers') AS AnswerCountStr,
  acs.AvgScore AS AverageCommentScore,
  lpe.LastEditDate,
  lpe.LastEditorDisplayName,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM PostLinks pl
      WHERE pl.PostId = p.Id
        AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  ('Tags: ' || COALESCE(p.Tags, '')) AS FormattedTags,
  COALESCE(eq.DisplayName, 'N/A') AS ExperiencedQuestioner,
  CASE
    WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId IN (
      SELECT UserId FROM Badges WHERE Class = 1
    ) THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS OwnerBadgeStatus,
  (
    p.Score * 5
    + COALESCE(p.ViewCount, 0) * 0.5
    + COALESCE(p.AnswerCount, 0) * 2
    + COALESCE(p.CommentCount, 0) * 1
    + COALESCE(acs.AvgScore, 0) * 3
    + (CASE WHEN lpe.LastEditDate IS NOT NULL THEN 1 ELSE 0 END) * 10
  ) AS EngagementScore
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN AvgCommentScore acs ON p.Id = acs.PostId
LEFT JOIN LatestPostEdit lpe ON p.Id = lpe.PostId AND lpe.rn = 1
LEFT JOIN ExperiencedQuestioners eq ON p.OwnerUserId = eq.UserId
WHERE
  p.PostTypeId IN (1, 2)
  AND p.CreationDate >= DATE '2023-01-01'
  AND (
    p.Score > 10
    OR p.ViewCount > 1000
    OR p.CommentCount > 5
  )
UNION ALL
SELECT
  CAST(NULL AS BIGINT) AS PostId,
  CAST(NULL AS VARCHAR) AS PostType,
  CAST(NULL AS VARCHAR) AS Title,
  CAST(NULL AS VARCHAR) AS OwnerDisplayName,
  CAST(NULL AS TIMESTAMP) AS CreationDate,
  CAST(NULL AS INTEGER) AS Score,
  CAST(NULL AS INTEGER) AS ViewCount,
  CAST(NULL AS VARCHAR) AS PostStatus,
  CAST(NULL AS VARCHAR) AS AnswerCountStr,
  CAST(NULL AS NUMERIC) AS AverageCommentScore,
  CAST(NULL AS TIMESTAMP) AS LastEditDate,
  CAST(NULL AS VARCHAR) AS LastEditorDisplayName,
  CAST(NULL AS VARCHAR) AS DuplicateLinkStatus,
  CAST(NULL AS VARCHAR) AS FormattedTags,
  'No Badge Users' AS ExperiencedQuestioner,
  CAST(NULL AS VARCHAR) AS OwnerBadgeStatus,
  CAST(-1.0 AS NUMERIC) AS EngagementScore
FROM Users u
WHERE NOT EXISTS (
  SELECT 1 FROM Badges b WHERE b.UserId = u.Id
)
LIMIT 5;