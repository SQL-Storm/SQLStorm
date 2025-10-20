SELECT 
  CAST(EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate)) AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)), 0) AS PostEditToActivityRatio,
  CAST(p.CommentCount AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)), 0) AS CommentPerSecond,
  CAST(p.AnswerCount AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)), 0) AS AnswerPerSecond,
  CAST(p.ViewCount AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)), 0) AS ViewPerSecond,
  CAST(p.FavoriteCount AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)), 0) AS FavoritePerSecond,
  CAST(COALESCE(u.UpVotes, 0) AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)), 0) AS UpVotePerSecond,
  CAST(COALESCE(u.DownVotes, 0) AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)), 0) AS DownVotePerSecond,
  CAST(COALESCE(b.Count, 0) AS DOUBLE PRECISION) / NULLIF(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - b.Date)), 0) AS BadgesPerSecond,
  p.Id,
  p.LastEditDate,
  p.CreationDate,
  p.LastActivityDate,
  p.CommentCount,
  p.AnswerCount,
  p.ViewCount,
  p.FavoriteCount,
  u.Id AS UserId,
  u.UpVotes,
  u.DownVotes,
  u.LastAccessDate,
  u.CreationDate,
  b.Count AS BadgeCount,
  b.Date AS BadgeDate
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