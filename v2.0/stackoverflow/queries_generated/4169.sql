-- {"query": "4169.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1021} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      u.Reputation,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS PostRankByOwner,
      AVG(CAST(p.Score AS FLOAT)) OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
      ) AS AvgScoreLast3Posts,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost
    FROM
      Posts AS p
      LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
      LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE
      p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
  ),
  UserEngagement AS (
    SELECT
      rp.OwnerUserId,
      COUNT(CASE WHEN rp.PostTypeId = 1 THEN rp.PostId END) AS QuestionCount,
      COUNT(CASE WHEN rp.PostTypeId = 2 THEN rp.PostId END) AS AnswerCount,
      SUM(CASE WHEN rp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostCount,
      MAX(rp.Reputation) AS MaxReputation,
      AVG(rp.Score) AS AvgScore,
      AVG(rp.AnswerCount) AS AvgAnswersPerQuestion,
      AVG(rp.FavoriteCount) AS AvgFavorites,
      AVG(rp.CommentCountForPost) AS AvgCommentsPerPost,
      SUM(rp.CommentCount) AS TotalComments
    FROM
      RankedPosts AS rp
    GROUP BY
      rp.OwnerUserId
  )
SELECT
  COALESCE(ue.OwnerUserId, rp.OwnerUserId) AS UserId,
  COALESCE(ue.QuestionCount, 0) AS TotalQuestions,
  COALESCE(ue.AnswerCount, 0) AS TotalAnswers,
  COALESCE(ue.ClosedPostCount, 0) AS PostsClosed,
  COALESCE(ue.MaxReputation, 0) AS UserMaxReputation,
  COALESCE(ue.AvgScore, 0) AS AvgPostScore,
  COALESCE(ue.AvgAnswersPerQuestion, 0) AS AvgAnswers,
  COALESCE(ue.AvgFavorites, 0) AS AvgFavorites,
  COALESCE(ue.AvgCommentsPerPost, 0) AS AvgComments,
  COALESCE(ue.TotalComments, 0) AS TotalCommentsByThisUser,
  rp.PostId AS MostRecentPostId,
  rp.PostRankByOwner AS RankOfMostRecentPost,
  rp.AvgScoreLast3Posts AS AvgScoreOfLast3Posts,
  CASE
    WHEN rp.PostRankByOwner <= 5 THEN 'Top 5 Most Recent'
    WHEN rp.PostRankByOwner <= 20 THEN 'Within Top 20'
    ELSE 'Older Posts'
  END AS RecentPostCategory,
  CASE
    WHEN COALESCE(ue.AvgScore, 0) > 50 THEN 'High Engagement'
    WHEN COALESCE(ue.AvgScore, 0) BETWEEN 10 AND 50 THEN 'Medium Engagement'
    ELSE 'Low Engagement'
  END AS EngagementLevel,
  SUBSTRING(u.DisplayName, 1, 3) AS DisplayNamePrefix,
  UPPER(u.DisplayName) AS DisplayNameUpper,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteType
FROM
  UserEngagement AS ue
FULL
  OUTER JOIN RankedPosts AS rp ON ue.OwnerUserId = rp.OwnerUserId
LEFT JOIN
  Users AS u ON COALESCE(ue.OwnerUserId, rp.OwnerUserId) = u.Id
WHERE
  ue.AnswerCount > 10
  OR rp.PostRankByOwner <= 10
ORDER BY
  UserMaxReputation DESC,
  TotalQuestions DESC;
