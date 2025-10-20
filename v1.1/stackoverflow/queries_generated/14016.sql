-- {"query": "14016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 39695, "output_tokens": 17784} 
WITH cte AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.CreationDate,
    p.OwnerUserId,
    p.Score, 
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CAST(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsClosed,
    CAST(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IsCommunityOwned,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
    LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
    LEAD(p.ViewCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostViewCount,
    LEAD(p.AnswerCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostAnswerCount,
    LEAD(p.CommentCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostCommentCount,
    LEAD(p.FavoriteCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostFavoriteCount,
    LEAD(CAST(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS BIT), 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostIsClosed,
    LEAD(CAST(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS BIT), 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostIsCommunityOwned
  FROM Posts p
),
user_stats AS (
  SELECT 
    OwnerUserId,
    COUNT(*) AS TotalPosts,
    SUM(Score) AS TotalScore,
    SUM(ViewCount) AS TotalViews,
    SUM(AnswerCount) AS TotalAnswers,
    SUM(CommentCount) AS TotalComments,
    SUM(FavoriteCount) AS TotalFavorites,
    SUM(CASE WHEN IsClosed = 1 THEN 1 ELSE 0 END) AS TotalClosed,
    SUM(CASE WHEN IsCommunityOwned = 1 THEN 1 ELSE 0 END) AS TotalCommunityOwned
  FROM cte
  GROUP BY OwnerUserId
)
SELECT
  c.Id,
  c.PostTypeId,
  c.CreationDate,
  c.OwnerUserId,
  c.Score,
  c.ViewCount,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.IsClosed,
  c.IsCommunityOwned,
  c.UserPostRank,
  c.NextPostScore,
  c.NextPostViewCount,
  c.NextPostAnswerCount,
  c.NextPostCommentCount,
  c.NextPostFavoriteCount,
  c.NextPostIsClosed,
  c.NextPostIsCommunityOwned,
  u.TotalPosts,
  u.TotalScore,
  u.TotalViews,
  u.TotalAnswers,
  u.TotalComments,
  u.TotalFavorites,
  u.TotalClosed,
  u.TotalCommunityOwned
FROM cte c
LEFT JOIN user_stats u ON c.OwnerUserId = u.OwnerUserId
ORDER BY c.Id;