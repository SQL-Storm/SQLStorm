-- {"query": "146.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1920} 
WITH LatestClosed AS (
  SELECT 
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    u.DisplayName,
    ph.CreationDate AS CloseDate,
    ph.Comment AS CloseComment
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  OUTER APPLY (
     SELECT TOP 1 ph1.CreationDate, ph1.Comment
     FROM PostHistory ph1
     WHERE ph1.PostId = p.Id AND ph1.PostHistoryTypeId = 10
     ORDER BY ph1.CreationDate DESC
  ) ph
  WHERE p.PostTypeId = 1
),
Enriched AS (
  SELECT 
    lc.Id,
    lc.Title,
    lc.CreationDate,
    lc.OwnerUserId,
    lc.ViewCount,
    lc.Score,
    lc.Tags,
    lc.DisplayName,
    lc.CloseDate,
    lc.CloseComment,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = lc.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = lc.Id AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = lc.Id AND v.VoteTypeId = 3) AS Downvotes
  FROM LatestClosed lc
),
Ranked AS (
  SELECT 
    e.*,
    ROW_NUMBER() OVER (ORDER BY e.ViewCount DESC, e.Upvotes DESC) AS rk,
    SUM(CASE WHEN e.CloseDate IS NOT NULL THEN 1 ELSE 0 END) OVER () AS CloseEventCount
  FROM Enriched e
)
SELECT *
FROM Ranked
WHERE rk <= 100
ORDER BY rk;