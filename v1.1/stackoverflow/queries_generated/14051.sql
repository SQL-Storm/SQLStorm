-- {"query": "14051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 121420, "output_tokens": 52389} 
WITH cte AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Body, 
    p.OwnerUserId, 
    p.CreationDate, 
    p.LastEditDate, 
    p.LastActivityDate, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    CASE WHEN p.ClosedDate IS NOT NULL THEN (SELECT c.Name FROM CloseReasonTypes c WHERE c.Id = (SELECT Comment FROM PostHistory WHERE PostId = p.Id AND PostHistoryTypeId = 10)) END AS CloseReason,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS user_post_rank,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) OVER (PARTITION BY p.Id) AS FavoriteVotes
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
),
cte2 AS (
  SELECT 
    cte.Id, 
    cte.Title, 
    cte.Body, 
    cte.OwnerUserId, 
    cte.CreationDate, 
    cte.LastEditDate, 
    cte.LastActivityDate, 
    cte.AnswerCount, 
    cte.CommentCount, 
    cte.FavoriteCount, 
    cte.ClosedDate, 
    cte.CommunityOwnedDate, 
    cte.CloseReason,
    cte.user_post_rank,
    cte.UpVotes,
    cte.DownVotes,
    cte.FavoriteVotes,
    CASE WHEN cte.ClosedDate IS NOT NULL THEN 'Closed'
         WHEN cte.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
         ELSE 'Open' END AS PostStatus,
    CASE WHEN cte.UpVotes > 0 THEN cte.UpVotes * 1.0 / (cte.UpVotes + cte.DownVotes) ELSE 0 END AS VoteRatio
  FROM cte
),
user_stats AS (
  SELECT 
    u.Id AS UserId, 
    u.Reputation, 
    u.CreationDate AS UserCreationDate, 
    u.LastAccessDate, 
    u.DisplayName, 
    u.WebsiteUrl, 
    u.Location, 
    u.AboutMe, 
    u.Views, 
    u.UpVotes AS UserUpVotes, 
    u.DownVotes AS UserDownVotes, 
    u.ProfileImageUrl, 
    u.EmailHash, 
    u.AccountId,
    COUNT(*) OVER (PARTITION BY u.Id) AS NumPosts,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
)
SELECT 
  cte2.Id, 
  cte2.Title, 
  cte2.Body, 
  cte2.OwnerUserId, 
  user_stats.DisplayName AS OwnerDisplayName,
  cte2.CreationDate, 
  cte2.LastEditDate, 
  cte2.LastActivityDate, 
  cte2.AnswerCount, 
  cte2.CommentCount, 
  cte2.FavoriteCount, 
  cte2.ClosedDate, 
  cte2.CommunityOwnedDate, 
  cte2.CloseReason, 
  cte2.user_post_rank,
  cte2.UpVotes, 
  cte2.DownVotes,
  cte2.FavoriteVotes,
  cte2.PostStatus,
  cte2.VoteRatio,
  user_stats.Reputation,
  user_stats.UserCreationDate,
  user_stats.LastAccessDate,
  user_stats.WebsiteUrl,
  user_stats.Location,
  user_stats.AboutMe,
  user_stats.Views,
  user_stats.UserUpVotes,
  user_stats.UserDownVotes,
  user_stats.ProfileImageUrl,
  user_stats.EmailHash,
  user_stats.AccountId,
  user_stats.NumPosts,
  user_stats.GoldBadges,
  user_stats.SilverBadges,
  user_stats.BronzeBadges
FROM cte2
LEFT JOIN user_stats ON cte2.OwnerUserId = user_stats.UserId
ORDER BY cte2.Id;