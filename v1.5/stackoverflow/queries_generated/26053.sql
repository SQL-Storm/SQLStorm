-- {"query": "26053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 514} 

WITH RECURSIVE PostHierarchy AS (
  SELECT Id, ParentId, 0 AS Level
  FROM Posts
  WHERE ParentId IS NULL
  UNION ALL
  SELECT p.Id, p.ParentId, Level + 1
  FROM Posts p
  JOIN PostHierarchy ph ON p.ParentId = ph.Id
),
UserBadges AS (
  SELECT u.Id, COUNT(b.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
),
PostScores AS (
  SELECT p.Id, SUM(v.VoteTypeId = 2) AS UpVotes, SUM(v.VoteTypeId = 3) AS DownVotes
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
)
SELECT 
  p.Id, 
  p.Score, 
  p.ViewCount, 
  p.Title, 
  ph.Level, 
  ub.BadgeCount, 
  ps.UpVotes, 
  ps.DownVotes, 
  COALESCE(u.Reputation, 0) AS Reputation, 
  COALESCE(u.LastAccessDate, p.CreationDate) AS LastAccessDate, 
  CASE 
    WHEN p.PostTypeId = 1 THEN 'Question'
    WHEN p.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostType,
  STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
  COUNT(DISTINCT pl.RelatedPostId) AS RelatedPostCount
FROM Posts p
JOIN PostHierarchy ph ON p.Id = ph.Id
LEFT JOIN UserBadges ub ON p.OwnerUserId = ub.Id
LEFT JOIN PostScores ps ON p.Id = ps.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostTags pt ON p.Id = pt.PostId
LEFT JOIN Tags t ON pt.TagId = t.Id
WHERE p.PostTypeId IN (1, 2)
  AND p.Score > 0
  AND p.ViewCount > 100
  AND p.CreationDate > NOW() - INTERVAL '1 year'
GROUP BY p.Id, p.Score, p.ViewCount, p.Title, ph.Level, ub.BadgeCount, ps.UpVotes, ps.DownVotes, u.Reputation, u.LastAccessDate
ORDER BY p.Score DESC, p.ViewCount DESC;
