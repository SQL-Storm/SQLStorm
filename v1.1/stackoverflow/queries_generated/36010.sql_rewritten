-- {"query": "36010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 443} 
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
  SELECT PostId, SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
                 SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY PostId
) pv ON pv.PostId = p.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS AvailableAuthorCount
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY PostId
) awk ON awk.PostId = p.Id
LEFT JOIN (
  SELECT RelatedPostId, COUNT(*) AS CountsByHour
  FROM PostLinks
  WHERE CreationDate >= date_trunc('hour', cast('2024-10-01 12:34:56' as timestamp) - interval '24 hours')
  GROUP BY RelatedPostId
) cl ON cl.RelatedPostId = p.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS UniqueLinkCount
  FROM PostLinks
  GROUP BY PostId
) bl ON bl.PostId = p.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) AS EditsLast30Days
  FROM PostHistory ph
  WHERE ph.PostId = ph.PostId
    AND ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
  GROUP BY PostId
) bh ON bh.PostId = p.Id
WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days'
  AND p.PostTypeId = 1
ORDER BY p.CreationDate DESC
LIMIT 100;