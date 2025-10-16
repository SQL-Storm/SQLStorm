-- {"query": "14064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 151775, "output_tokens": 65279} 
WITH cte AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Open'
    END AS PostStatus,
    COALESCE(ph.Comment, '') AS CloseReason,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserScoreRank,
    CASE
      WHEN p.OwnerUserId = p.LastEditorUserId THEN 'Author'
      ELSE 'Edited'
    END AS PostEditType,
    CASE
      WHEN p.OwnerUserId = p.LastEditorUserId THEN 1
      ELSE 0
    END AS IsAuthorEdit,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF(p.ClosedDate, p.CreationDate)
      ELSE DATEDIFF(p.LastActivityDate, p.CreationDate)
    END AS DaysActive,
    CASE
      WHEN p.AnswerCount > 0 THEN 'Answered'
      ELSE 'Unanswered'
    END AS AnswerStatus,
    CASE
      WHEN p.FavoriteCount > 0 THEN 'Favorited'
      ELSE 'Not Favorited'
    END AS FavoriteStatus
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
),
user_stats AS (
  SELECT
    OwnerUserId,
    MAX(Score) AS MaxScore,
    AVG(Score) AS AvgScore,
    COUNT(*) AS PostCount,
    SUM(AnswerCount) AS AnsweredPosts,
    SUM(CASE WHEN AnswerStatus = 'Answered' THEN 1 ELSE 0 END) AS AnsweredQuestionsCount,
    SUM(CASE WHEN FavoriteStatus = 'Favorited' THEN 1 ELSE 0 END) AS FavoritedPostsCount,
    SUM(CASE WHEN PostStatus = 'Closed' THEN 1 ELSE 0 END) AS ClosedPostsCount,
    SUM(CASE WHEN PostStatus = 'Community Owned' THEN 1 ELSE 0 END) AS CommunityOwnedPostsCount
  FROM cte
  GROUP BY OwnerUserId
)
SELECT
  cte.PostId,
  cte.Title,
  cte.OwnerUserId,
  cte.CreationDate,
  cte.LastActivityDate,
  cte.Score,
  cte.AnswerCount,
  cte.CommentCount,
  cte.FavoriteCount,
  cte.PostStatus,
  cte.CloseReason,
  cte.UserScoreRank,
  cte.PostEditType,
  cte.IsAuthorEdit,
  cte.DaysActive,
  cte.AnswerStatus,
  cte.FavoriteStatus,
  user_stats.MaxScore,
  user_stats.AvgScore,
  user_stats.PostCount,
  user_stats.AnsweredPosts,
  user_stats.AnsweredQuestionsCount,
  user_stats.FavoritedPostsCount,
  user_stats.ClosedPostsCount,
  user_stats.CommunityOwnedPostsCount
FROM cte
LEFT JOIN user_stats ON cte.OwnerUserId = user_stats.OwnerUserId
ORDER BY cte.Score DESC, cte.CreationDate DESC
LIMIT 100;