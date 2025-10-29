-- {"query": "5311.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 384} 
SELECT
  u.DisplayName AS detector,
  COUNT(*) AS total_events,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
  AVG(tD.Delta) AS avg_user_reputation_delta,
  MAX(p.LastActivityDate) AS most_recent_activity,
  STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN CONCAT(p.Title, ' [Q]') ELSE CONCAT(p.Title, ' [A]') END, ' | ') AS sample_titles,
  ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE vl.is_link = TRUE) AS distant_link_types
FROM
  Votes v
  INNER JOIN Posts p ON v.PostId = p.Id
  INNER JOIN Users u ON v.UserId = u.Id
  LEFT JOIN LATERAL (
    SELECT
      (u.Reputation - COALESCE(p.ReputationAtVote, 0)) AS Delta
  ) tD ON TRUE
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN (SELECT Id, Name, 1 AS is_link FROM LinkTypes) lt ON pl.LinkTypeId = lt.Id
  LEFT JOIN (SELECT 1 AS is_link) vl ON pl.PostId = p.Id
WHERE
  v.CreationDate >= NOW() - INTERVAL '30 days'
  AND p.CreationDate >= NOW() - INTERVAL '180 days'
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(*) > 100
ORDER BY
  total_events DESC
LIMIT 1;