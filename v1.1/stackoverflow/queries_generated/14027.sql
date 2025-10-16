-- {"query": "14027.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 65380, "output_tokens": 29420} 
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, u.Reputation, u.Location, u.AccountId, u.DisplayName, u.EmailHash, u.UpVotes, u.DownVotes,
         CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered' ELSE 'Unanswered' END AS AnswerStatus,
         CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
         STRING_AGG(DISTINCT t.TagName, ',') AS Tags,
         COALESCE(p.AnswerCount, 0) AS AnswerCount,
         COALESCE(p.CommentCount, 0) AS CommentCount,
         COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
         COALESCE(p.Score, 0) AS Score,
         COALESCE(p.ViewCount, 0) AS ViewCount
  FROM Posts p
  LEFT JOIN Tags t ON CHARINDEX('<' + t.TagName + '>', p.Tags) > 0
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, u.Reputation, u.Location, u.AccountId, u.DisplayName, u.EmailHash, u.UpVotes, u.DownVotes, p.AcceptedAnswerId, p.ClosedDate, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Score, p.ViewCount
),
user_stats AS (
  SELECT OwnerUserId, 
         COUNT(*) AS TotalPosts,
         SUM(CASE WHEN AnswerStatus = 'Answered' THEN 1 ELSE 0 END) AS AnsweredPosts,
         SUM(CASE WHEN PostStatus = 'Closed' THEN 1 ELSE 0 END) AS ClosedPosts,
         SUM(FavoriteCount) AS TotalFavorites,
         SUM(AnswerCount) AS TotalAnswers,
         SUM(CommentCount) AS TotalComments,
         SUM(Score) AS TotalScore,
         SUM(ViewCount) AS TotalViews
  FROM cte
  GROUP BY OwnerUserId
)
SELECT c.Id, c.PostTypeId, c.CreationDate, c.OwnerUserId, c.Reputation, c.Location, c.AccountId, c.DisplayName, c.EmailHash, c.UpVotes, c.DownVotes, 
       c.AnswerStatus, c.PostStatus, c.Tags, c.AnswerCount, c.CommentCount, c.FavoriteCount, c.Score, c.ViewCount,
       u.TotalPosts, u.AnsweredPosts, u.ClosedPosts, u.TotalFavorites, u.TotalAnswers, u.TotalComments, u.TotalScore, u.TotalViews
FROM cte c
LEFT JOIN user_stats u ON c.OwnerUserId = u.OwnerUserId
ORDER BY c.CreationDate DESC, c.Id;