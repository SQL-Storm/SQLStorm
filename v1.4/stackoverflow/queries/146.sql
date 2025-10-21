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
  LEFT JOIN (
     SELECT ph1.PostId,
            ph1.CreationDate,
            ph1.Comment
     FROM PostHistory ph1
     WHERE ph1.PostHistoryTypeId = 10
  ) ph ON ph.PostId = p.Id
  WHERE p.PostTypeId = 1
  ORDER BY ph.CreationDate DESC
  LIMIT 1
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