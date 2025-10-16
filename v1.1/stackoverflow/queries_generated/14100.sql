-- {"query": "14100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 669} 
Here is an elaborate SQL query that performs performance benchmarking using various constructs:

WITH cte AS (
  SELECT p.Id, p.Title, p.Body, p.Tags, p.OwnerUserId, p.CreationDate, 
         DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
), top_posts AS (
  SELECT Id, Title, Body, Tags, OwnerUserId, CreationDate
  FROM cte
  WHERE rn <= 10
)
SELECT 
  p.Id, 
  p.Title,
  CONCAT(SUBSTRING(p.Body, 1, 100), '...') AS Body_Snippet,
  CONCAT('[', REPLACE(p.Tags, '<', ''), ']') AS Tags,
  u.DisplayName AS OwnerName,
  DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) AS DaysSinceCreation,
  CASE 
    WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Duplicate'
    WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 6) THEN 'Closed'
    WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 7) THEN 'Reopened'
    ELSE 'Open'
  END AS PostStatus,
  COALESCE(NULLIF(SUBSTRING_INDEX(SUBSTRING_INDEX(p.Tags, '><', 1), '>', -1), ''), 'None') AS PrimaryTag,
  IFNULL(CAST(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS SIGNED), 0) AS UpVotes,
  IFNULL(CAST(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS SIGNED), 0) AS DownVotes,
  IFNULL(COUNT(c.Id), 0) AS CommentCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.Id IN (SELECT Id FROM top_posts)
GROUP BY p.Id
ORDER BY DaysSinceCreation DESC
LIMIT 50;