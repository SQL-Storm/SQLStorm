-- {"query": "14019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 46700, "output_tokens": 20702} 
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, u.Reputation, u.CreationDate AS UserCreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, b.Id AS BadgeId, b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, b.TagBased AS BadgeTagBased
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
  WHERE p.PostTypeId = 1 -- Questions only
),
top_posts AS (
  SELECT Id, PostTypeId, OwnerUserId, CreationDate, LastEditDate, LastActivityDate, Title, Tags, AnswerCount, CommentCount, FavoriteCount, ClosedDate, CommunityOwnedDate, Reputation, UserCreationDate, LastAccessDate, Views, UpVotes, DownVotes, BadgeId, BadgeName, BadgeDate, BadgeClass, BadgeTagBased,
  ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY FavoriteCount DESC, AnswerCount DESC, CommentCount DESC) AS rn
  FROM cte
)
SELECT 
  tp.Id, 
  tp.PostTypeId, 
  tp.OwnerUserId, 
  tp.CreationDate, 
  tp.LastEditDate, 
  tp.LastActivityDate, 
  tp.Title, 
  tp.Tags, 
  tp.AnswerCount, 
  tp.CommentCount, 
  tp.FavoriteCount, 
  tp.ClosedDate, 
  tp.CommunityOwnedDate, 
  tp.Reputation, 
  tp.UserCreationDate, 
  tp.LastAccessDate, 
  tp.Views, 
  tp.UpVotes, 
  tp.DownVotes,
  tp.BadgeId,
  tp.BadgeName,
  tp.BadgeDate,
  tp.BadgeClass,
  tp.BadgeTagBased,
  CASE 
    WHEN tp.rn = 1 THEN 'Top Post'
    WHEN tp.rn <= 3 THEN 'Top 3 Posts'
    WHEN tp.rn <= 10 THEN 'Top 10 Posts'
    ELSE 'Other Posts' 
  END AS PostRank
FROM top_posts tp
WHERE tp.rn <= 10;