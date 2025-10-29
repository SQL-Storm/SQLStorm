-- {"query": "5566.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 888}
WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditDate,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
TopTagWikis AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
Filtered AS (
  SELECT
    ra.PostId,
    ra.OwnerUserId,
    ra.Title,
    ra.Tags,
    ra.Score,
    ra.ViewCount,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.PostTypeId,
    ra.AcceptedAnswerId,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.Body,
    ra.LastEditDate,
    ra.Reputation,
    ra.OwnerDisplayName,
    ra.rn,
    STRING_AGG(DISTINCT CAST(v.VoteTypeId AS VARCHAR), ',') AS VoteTypesApplied,
    COUNT(DISTINCT c.Id) AS CommentCountLive
  FROM RecentActive ra
  LEFT JOIN Votes v ON ra.PostId = v.PostId
  LEFT JOIN Comments c ON ra.PostId = c.PostId
  GROUP BY
    ra.PostId, ra.OwnerUserId, ra.Title, ra.Tags, ra.Score, ra.ViewCount,
    ra.CreationDate, ra.LastActivityDate, ra.PostTypeId, ra.AcceptedAnswerId,
    ra.CommentCount, ra.FavoriteCount, ra.Body, ra.LastEditDate, ra.Reputation,
    ra.OwnerDisplayName, ra.rn
  HAVING ra.LastActivityDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
),
CorrelatedStats AS (
  SELECT
    f.*,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = f.OwnerUserId AND p2.CreationDate > f.CreationDate - INTERVAL '365' DAY) AS AvgOwnerLifecycleScore,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = f.OwnerUserId AND p3.PostTypeId = 1) AS TotalQuestionsByOwner,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = f.PostId) AS LinkCount
  FROM Filtered f
),
Windowed AS (
  SELECT
    cs.*,
    ROW_NUMBER() OVER (PARTITION BY cs.OwnerUserId ORDER BY cs.LastActivityDate DESC) AS RankByOwner
  FROM CorrelatedStats cs
)
SELECT
  w.PostId,
  w.OwnerUserId,
  w.OwnerDisplayName,
  w.Title,
  w.Tags,
  w.Score,
  w.ViewCount,
  w.CreationDate,
  w.LastActivityDate,
  w.PostTypeId,
  w.AcceptedAnswerId,
  w.CommentCount,
  w.FavoriteCount,
  w.Body,
  w.LastEditDate,
  w.Reputation,
  w.AvgOwnerLifecycleScore,
  w.TotalQuestionsByOwner,
  w.LinkCount,
  w.VoteTypesApplied,
  w.CommentCountLive,
  CASE
    WHEN w.PostTypeId = 1 THEN 'Question'
    WHEN w.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  CASE
    WHEN w.RankByOwner = 1 THEN 'Top by owner in 180d'
    ELSE NULL
  END AS HighlightFlag
FROM Windowed w
WHERE w.RankByOwner <= 5
ORDER BY w.LastActivityDate DESC, w.Score DESC;