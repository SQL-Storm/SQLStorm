SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.Tags,
  p.LastActivityDate,
  pv.TotalUpVotes,
  pv.TotalDownVotes,
  awk.AvailableAuthorCount,
  cl.CountsByHour,
  bl.UniqueLinkCount,
  bh.EditsLast30Days
FROM Posts p
LEFT JOIN (
  SELECT v.PostId, 
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY v.PostId
) pv ON pv.PostId = p.Id
LEFT JOIN LATERAL (
  SELECT p2.Id AS PostId, COUNT(*) AS AvailableAuthorCount
  FROM Posts p2
  WHERE p2.Id = p.Id
    AND p2.OwnerUserId IS NOT NULL
  GROUP BY p2.Id
) awk ON true
LEFT JOIN (
  SELECT pl.RelatedPostId, COUNT(*) AS CountsByHour
  FROM PostLinks pl
  WHERE pl.CreationDate >= date_trunc('hour', cast('2024-10-01 12:34:56' AS timestamp) - interval '24 hours')
  GROUP BY pl.RelatedPostId
) cl ON cl.RelatedPostId = p.Id
LEFT JOIN (
  SELECT pl2.PostId, COUNT(*) AS UniqueLinkCount
  FROM PostLinks pl2
  GROUP BY pl2.PostId
) bl ON bl.PostId = p.Id
LEFT JOIN (
  SELECT ph.PostId, COUNT(*) AS EditsLast30Days
  FROM PostHistory ph
  WHERE ph.CreationDate >= cast('2024-10-01 12:34:56' AS timestamp) - interval '30 days'
  GROUP BY ph.PostId
) bh ON bh.PostId = p.Id
WHERE p.CreationDate >= cast('2024-10-01 12:34:56' AS timestamp) - interval '180 days'
  AND p.PostTypeId = 1
ORDER BY p.CreationDate DESC
LIMIT 100;