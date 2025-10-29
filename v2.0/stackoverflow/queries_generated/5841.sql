-- {"query": "5841.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 880} 
WITH
  -- recent activity per post with derived metrics
  RecentActivity AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.Title,
      p.CreationDate,
      p.LastActivityDate,
      p.OwnerUserId,
      p.ViewCount,
      p.Score,
      p.Tags,
      COALESCE(a.CommentCount, 0) AS CommentCount,
      COALESCE(v.UpModCount, 0) AS UpModCount,
      COALESCE(v.DownModCount, 0) AS DownModCount,
      COALESCE(b.BadgeCount, 0) AS BadgeCount
    FROM Posts p
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS CommentCount
      FROM Comments
      GROUP BY PostId
    ) a ON a.PostId = p.Id
    LEFT JOIN (
      SELECT PostId,
             SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpModCount,
             SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownModCount
      FROM Votes v
      JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
      GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN (
      SELECT PostId, COUNT(*) AS BadgeCount
      FROM PostBadgesFunctionDummy -- placeholder: simulate badge count per post (replace with real join if needed)
      GROUP BY PostId
    ) b ON b.PostId = p.Id
  ),
  -- top related posts by tag similarity via string proximity on Tags
  TagSimilarity AS (
    SELECT
      p1.Id AS PostId,
      p1.Tags,
      CASE
        WHEN p2.Id IS NULL THEN 0
        ELSE (LENGTH(p1.Tags) - LENGTH(REPLACE(p1.Tags, CONCAT('<', TRIM(p2.Tags), '>'), ''))) / NULLIF(LENGTH(CONCAT('<', TRIM(p2.Tags), '>')), 0)
      END AS Similarity
    FROM Posts p1
    LEFT JOIN Posts p2 ON p1.OwnerUserId = p2.OwnerUserId AND p2.Id <> p1.Id
  ),
  -- windowed ranking by activity within last 30 days
  ActivityRank AS (
    SELECT
      ra.PostId,
      ra.PostTypeId,
      ra.Title,
      ra.CreationDate,
      ra.LastActivityDate,
      ra.ViewCount,
      ra.Score,
      ra.CommentCount,
      ra.UpModCount,
      ra.DownModCount,
      ra.BadgeCount,
      ROW_NUMBER() OVER (
        PARTITION BY ra.PostTypeId
        ORDER BY ra.Score * 2 + ra.ViewCount * 0.5 + ra.CommentCount * 1.2 + ra.UpModCount - ra.DownModCount DESC
      ) AS RN
    FROM RecentActivity ra
  ),
  -- cross join to generate a challenging predicate with NULL handling and complex expressions
  ComplexFilter AS (
    SELECT
      ar.*,
      CASE
        WHEN ar.ViewCount IS NULL THEN 0
        ELSE ar.ViewCount
      END AS vc,
      CASE
        WHEN ar.Score IS NULL THEN 0
        ELSE ar.Score
      END AS sc,
      CASE
        WHEN ar.CommentCount IS NULL THEN 0
        ELSE ar.CommentCount
      END AS com
    FROM ActivityRank ar
  )
SELECT
  cf.PostId,
  cf.Title,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.ViewCount,
  cf.Score,
  cf.CommentCount,
  cf.UpModCount,
  cf.DownModCount,
  cf.BadgeCount,
  cf.vc,
  cf.sc,
  cf.com,
  cf.Similarity
FROM ComplexFilter cf
LEFT JOIN TagSimilarity ts ON ts.PostId = cf.PostId
WHERE
  cf.RN <= 100
  AND (
    (cf.sc > 0 AND cf.com > 0) OR
    (cf.SubQueryFlag IS NULL OR cf.SubQueryFlag = 1)
  )
ORDER BY cf.LastActivityDate DESC, cf.Score DESC;