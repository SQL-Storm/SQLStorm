-- {"query": "44047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 107818, "output_tokens": 38651} 

SELECT
  p.Id AS PostId,
  p.Title,
  p.Body,
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.Location,
  CONCAT(DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate), ' days') AS PostAgeInDays,
  CONCAT(DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate), ' days') AS UserAgeInDays,
  CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
  COALESCE(cl.Name, 'Not Closed') AS CloseReason,
  COALESCE(COUNT(DISTINCT pl.Id), 0) AS LinkCount,
  COALESCE(COUNT(DISTINCT v.Id), 0) AS VoteCount,
  COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
  COALESCE(COUNT(DISTINCT b.Id), 0) AS BadgeCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN CloseReasonTypes cl ON ph.Comment = CAST(cl.Id AS VARCHAR(50))
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE p.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 YEAR)
GROUP BY p.Id, u.Id
ORDER BY p.ViewCount DESC
LIMIT 100;
```

This SQL query is designed for performance benchmarking of the StackOverflow database schema. It retrieves the top 100 posts created within the last year, along with various related data such as user information, post status, close reason, and counts of related entities (links, votes, comments, badges). The query utilizes multiple joins to gather the necessary data and performs aggregations to summarize the information.