-- {"query": "44002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 497}

SELECT 
  CAST(DATEDIFF(SECOND, p.CreationDate, p.LastEditDate) AS FLOAT) / DATEDIFF(SECOND, p.CreationDate, p.LastActivityDate) AS PostEditToActivityRatio,
  CAST(p.CommentCount AS FLOAT) / DATEDIFF(SECOND, p.CreationDate, p.LastActivityDate) AS CommentPerSecond,
  CAST(p.AnswerCount AS FLOAT) / DATEDIFF(SECOND, p.CreationDate, p.LastActivityDate) AS AnswerPerSecond,
  CAST(p.ViewCount AS FLOAT) / DATEDIFF(SECOND, p.CreationDate, p.LastActivityDate) AS ViewPerSecond,
  CAST(p.FavoriteCount AS FLOAT) / DATEDIFF(SECOND, p.CreationDate, p.LastActivityDate) AS FavoritePerSecond,
  CAST(COALESCE(u.UpVotes, 0) AS FLOAT) / DATEDIFF(SECOND, u.CreationDate, u.LastAccessDate) AS UpVotePerSecond,
  CAST(COALESCE(u.DownVotes, 0) AS FLOAT) / DATEDIFF(SECOND, u.CreationDate, u.LastAccessDate) AS DownVotePerSecond,
  CAST(COALESCE(b.Count, 0) AS FLOAT) / DATEDIFF(SECOND, b.Date, CURRENT_TIMESTAMP) AS BadgesPerSecond
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT 
    UserId, 
    COUNT(*) AS Count, 
    MAX(Date) AS Date 
  FROM Badges
  GROUP BY UserId
) b ON p.OwnerUserId = b.UserId
WHERE p.PostTypeId = 1
ORDER BY CommentPerSecond DESC
LIMIT 10;
