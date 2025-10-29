-- {"query": "14030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 468}
WITH cte AS (
  SELECT p.Id, p.Title, p.Body, p.CreationDate, p.OwnerUserId, 
         DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS user_post_rank
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_posts AS (
  SELECT Id, Title, Body, CreationDate, OwnerUserId
  FROM cte
  WHERE user_post_rank <= 3
)
SELECT 
  t.Title,
  t.Body,
  t.CreationDate,
  u.DisplayName,
  u.Location,
  u.WebsiteUrl,
  u.AboutMe,
  COALESCE(b.Name, 'No Badges') AS Badges,
  COALESCE(CAST(SUM(v.BountyAmount) AS VARCHAR(10)), '0') AS TotalBounty,
  COALESCE(CAST(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS VARCHAR(10)), '0') AS UpVotes,
  COALESCE(CAST(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS VARCHAR(10)), '0') AS DownVotes
FROM top_posts t
LEFT JOIN Users u ON t.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON t.Id = v.PostId
GROUP BY t.Title, t.Body, t.CreationDate, u.DisplayName, u.Location, u.WebsiteUrl, u.AboutMe, b.Name
ORDER BY TotalBounty DESC, UpVotes DESC, DownVotes ASC
LIMIT 10;
