-- {"query": "5664.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1198} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate > NOW() - INTERVAL '30 days'
    AND p.Online = 1 -- if the schema had an Online flag; keep if not, remove this predicate
),
TaggedActivity AS (
  SELECT
    ra.PostId,
    ra.OwnerUserId,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    b.Name AS BadgeName,
    COUNT(*) OVER () AS total_count
  FROM RecentActivePosts ra
  LEFT JOIN Badges b ON ra.OwnerUserId = b.UserId
  WHERE ra.Tags IS NOT NULL
),
Linkage AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
ScoreDistribution AS (
  SELECT
    p.PostTypeId,
    CASE
      WHEN p.Score >= 100 THEN 'A'
      WHEN p.Score >= 50 THEN 'B'
      WHEN p.Score >= 10 THEN 'C'
      WHEN p.Score >= 0 THEN 'D'
      ELSE 'E'
    END AS ScoreBand,
    COUNT(*) AS NumPosts
  FROM Posts p
  GROUP BY p.PostTypeId, CASE
      WHEN p.Score >= 100 THEN 'A'
      WHEN p.Score >= 50 THEN 'B'
      WHEN p.Score >= 10 THEN 'C'
      WHEN p.Score >= 0 THEN 'D'
      ELSE 'E'
    END
),
ComplexPredicate AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    CASE
      WHEN p.FavoriteCount > 0 THEN 1
      WHEN p.CommentCount > 20 THEN 1
      ELSE 0
    END AS IsHighlyEngaged,
    CASE
      WHEN p.LastEditorUserId IS NOT NULL THEN p.LastEditorDisplayName
      ELSE p.OwnerDisplayName
    END AS EditorOrOwner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate > NOW() - INTERVAL '14 days'
    AND (p.Score > 0 OR p.ViewCount > 500)
),
OuterJoinExample AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.Text,
    c.UserId,
    c.CreationDate,
    u.DisplayName AS Commenter
  FROM Comments c
  LEFT JOIN Users u ON c.UserId = u.Id
  RIGHT JOIN Posts p ON p.Id = c.PostId AND p.PostTypeId = 1
),
CorrelatedSubquery AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountForPost
  FROM Posts p
  WHERE p.PostTypeId = 1
),
WindowFunctionExample AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS CumulativeViewsByOwner
  FROM Posts p
),
SetOperatorExample AS (
  SELECT Id, Title, CreationDate FROM Posts WHERE PostTypeId = 1
  UNION ALL
  SELECT Id, Title, CreationDate FROM Posts WHERE PostTypeId = 2
)
SELECT
  rp.PostId,
  rp.Title,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.Tags,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.PostTypeId,
  rp.ParentId,
  rp.AcceptedAnswerId,
  rp.Body,
  rp.ContentLicense,
  ru.Reputation,
  ru.Location,
  ru.AccountId,
  ru.UserCreationDate,
  COALESCE(la.total_count, 0) AS TotalBadgesForOwner,
  le.EditorOrOwner
FROM (
  SELECT *
  FROM ComplexPredicate
) rp
LEFT JOIN Users ru ON rp.OwnerUserId = ru.Id
LEFT JOIN TaggedActivity ta ON rp.Id = ta.PostId
LEFT JOIN OuterJoinExample oje ON rp.Id = oje.PostId
LEFT JOIN CorrelatedSubquery cs ON rp.Id = cs.PostId
LEFT JOIN WindowFunctionExample wfe ON rp.Id = wfe.Id
LEFT JOIN SetOperatorExample soe ON rp.Id = soe.Id
ORDER BY rp.LastActivityDate DESC
LIMIT 100;