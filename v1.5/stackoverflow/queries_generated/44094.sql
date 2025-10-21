-- {"query": "44094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 712}
Here is an elaborate SQL query for performance benchmarking on the StackOverflow database schema:

WITH cte_user_stats AS (
  SELECT u.Id, 
         u.Reputation, 
         u.UpVotes, 
         u.DownVotes, 
         (u.UpVotes - u.DownVotes) AS net_votes,
         COUNT(b.Id) AS num_badges
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
),
cte_post_stats AS (
  SELECT p.Id, 
         p.PostTypeId, 
         p.CreationDate, 
         p.Score, 
         p.ViewCount, 
         p.AnswerCount, 
         p.CommentCount, 
         p.FavoriteCount,
         CASE WHEN p.ClosedDate IS NULL THEN 0 ELSE 1 END AS is_closed,
         CASE WHEN p.CommunityOwnedDate IS NULL THEN 0 ELSE 1 END AS is_community_owned
  FROM Posts p
),
cte_vote_stats AS (
  SELECT v.PostId, 
         COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
         COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes,
         COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorites
  FROM Votes v
  GROUP BY v.PostId
),
cte_comment_stats AS (
  SELECT c.PostId, 
         COUNT(*) AS comment_count
  FROM Comments c
  GROUP BY c.PostId
)
SELECT 
  u.Id AS user_id,
  u.Reputation,
  u.UpVotes,
  u.DownVotes,
  u.net_votes,
  u.num_badges,
  p.Id AS post_id,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.is_closed,
  p.is_community_owned,
  vs.upvotes,
  vs.downvotes,
  vs.favorites,
  cs.comment_count
FROM cte_user_stats u
JOIN cte_post_stats p ON u.Id = p.OwnerUserId
LEFT JOIN cte_vote_stats vs ON p.Id = vs.PostId
LEFT JOIN cte_comment_stats cs ON p.Id = cs.PostId
ORDER BY p.ViewCount DESC
LIMIT 100;
