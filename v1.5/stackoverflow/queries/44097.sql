WITH cte AS (
  SELECT p.Id AS PostId,
         p.PostTypeId,
         p.CreationDate,
         p.OwnerUserId,
         p.ViewCount,
         p.Score,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount,
         u.Reputation,
         u.CreationDate AS UserCreationDate,
         u.LastAccessDate,
         u.Views AS UserViews,
         u.UpVotes AS UserUpVotes,
         u.DownVotes AS UserDownVotes
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
posts_cte AS (
  SELECT PostId,
         PostTypeId,
         CreationDate,
         OwnerUserId,
         ViewCount,
         Score,
         AnswerCount,
         CommentCount,
         FavoriteCount,
         Reputation,
         UserCreationDate,
         LastAccessDate,
         UserViews,
         UserUpVotes,
         UserDownVotes,
         (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - CreationDate) AS PostAgeDays,
         (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - UserCreationDate) AS UserAgeDays,
         (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - LastAccessDate) AS LastAccessDays
  FROM cte
),
vote_counts AS (
  SELECT PostId,
         COUNT(*) AS VoteCount
  FROM Votes
  WHERE VoteTypeId IN (2, 3)
  GROUP BY PostId
)
SELECT
  p.PostId,
  p.PostTypeId,
  p.CreationDate,
  p.OwnerUserId,
  p.ViewCount,
  p.Score,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.Reputation,
  p.UserCreationDate,
  p.LastAccessDate,
  p.UserViews,
  p.UserUpVotes,
  p.UserDownVotes,
  p.PostAgeDays,
  p.UserAgeDays,
  p.LastAccessDays,
  vc.VoteCount
FROM posts_cte p
LEFT JOIN vote_counts vc ON p.PostId = vc.PostId
ORDER BY p.PostAgeDays DESC,
         p.Score DESC,
         p.ViewCount DESC,
         p.AnswerCount DESC,
         p.CommentCount DESC,
         p.FavoriteCount DESC,
         COALESCE(vc.VoteCount, 0) DESC;