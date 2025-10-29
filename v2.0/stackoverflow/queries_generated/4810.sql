-- {"query": "4810.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1819} 

WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      p.Id AS PostId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.ClosedDate AS PostClosedDate,
      COUNT(c.Id) AS CommentCountOnPost,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSeqNum
    FROM
      Posts AS p
      LEFT JOIN Comments AS c
        ON p.Id = c.PostId
      LEFT JOIN Votes AS v
        ON p.Id = v.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId,
      p.Id,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate
  ),
  UserBadgeStats AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
      MAX(b.Date) AS LastBadgeDate
    FROM
      Badges AS b
    GROUP BY
      b.UserId
  ),
  UserPostSummary AS (
    SELECT
      upa.OwnerUserId,
      COUNT(DISTINCT CASE WHEN upa.PostTypeId = 1 THEN upa.PostId END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN upa.PostTypeId = 2 THEN upa.PostId END) AS AnswerCount,
      AVG(upa.PostScore) AS AvgPostScore,
      SUM(upa.PostViewCount) AS TotalPostViews,
      SUM(upa.PostFavoriteCount) AS TotalFavorites,
      COUNT(DISTINCT CASE WHEN upa.PostClosedDate IS NOT NULL THEN upa.PostId END) AS ClosedPostCount,
      MAX(upa.PostCreationDate) AS LatestPostDate,
      MAX(upa.PostSeqNum) AS TotalPostsByThisUser
    FROM
      UserPostActivity AS upa
    GROUP BY
      upa.OwnerUserId
  ),
  UserActivityMetrics AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      u.LastAccessDate,
      COALESCE(ups.QuestionCount, 0) AS TotalQuestions,
      COALESCE(ups.AnswerCount, 0) AS TotalAnswers,
      COALESCE(ups.AvgPostScore, 0) AS AveragePostScore,
      COALESCE(ups.TotalPostViews, 0) AS TotalPostViews,
      COALESCE(ups.TotalFavorites, 0) AS TotalPostFavorites,
      COALESCE(ups.ClosedPostCount, 0) AS TotalClosedPosts,
      COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
      COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
      COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
      CASE WHEN COALESCE(ubs.LastBadgeDate, '1900-01-01') > COALESCE(ups.LatestPostDate, '1900-01-01') THEN ubs.LastBadgeDate ELSE ups.LatestPostDate END AS LastActivityDate,
      DATEDIFF(day, u.CreationDate, GETDATE()) AS DaysSinceCreation,
      (
        u.Reputation * 1.0 / NULLIF(DATEDIFF(day, u.CreationDate, GETDATE()), 0)
      ) AS ReputationPerDay,
      SUBSTRING(u.AboutMe, 1, 50) AS AboutMeSnippet,
      CASE
        WHEN u.WebsiteUrl IS NULL
        THEN 'No Website'
        WHEN CHARINDEX('stackoverflow.com', u.WebsiteUrl) > 0
        THEN 'Stack Exchange Site'
        ELSE 'External Website'
      END AS WebsiteCategory,
      CASE
        WHEN COALESCE(ups.TotalAnswers, 0) > 0
        THEN CAST(COALESCE(ups.TotalAnswers, 0) AS REAL) / NULLIF(ups.TotalQuestions, 0)
        ELSE 0.0
      END AS AnswerToQuestionRatio
    FROM
      Users AS u
      LEFT JOIN UserPostSummary AS ups
        ON u.Id = ups.OwnerUserId
      LEFT JOIN UserBadgeStats AS ubs
        ON u.Id = ubs.UserId
  )
SELECT
  uam.*,
  CASE
    WHEN uam.ReputationPerDay > 100
    AND uam.TotalQuestions > 50
    AND uam.TotalAnswers > 100
    THEN 'High Performer'
    WHEN uam.ReputationPerDay > 10
    AND uam.TotalQuestions > 10
    THEN 'Active Contributor'
    WHEN uam.Reputation < 500
    AND uam.DaysSinceCreation > 365
    THEN 'Low Engagement User'
    ELSE 'Standard User'
  END AS UserTier,
  LAG(uam.Reputation, 1, 0) OVER (ORDER BY uam.UserCreationDate) AS PreviousUserReputation,
  LEAD(uam.Reputation, 1, 0) OVER (ORDER BY uam.UserCreationDate) AS NextUserReputation,
  CASE
    WHEN uam.AnswerToQuestionRatio BETWEEN 0 AND 0.5 THEN 'Low Answer Rate'
    WHEN uam.AnswerToQuestionRatio BETWEEN 0.5 AND 2 THEN 'Balanced'
    WHEN uam.AnswerToQuestionRatio > 2 THEN 'High Answer Rate'
    ELSE 'No Answers'
  END AS AnswerProfile
FROM
  UserActivityMetrics AS uam
WHERE
  uam.UserCreationDate BETWEEN '2020-01-01' AND '2022-12-31'
  AND uam.Reputation > 1000
UNION ALL
SELECT
  uam.*,
  'Veteran User' AS UserTier,
  LAG(uam.Reputation, 1, 0) OVER (ORDER BY uam.UserCreationDate) AS PreviousUserReputation,
  LEAD(uam.Reputation, 1, 0) OVER (ORDER BY uam.UserCreationDate) AS NextUserReputation,
  CASE
    WHEN uam.AnswerToQuestionRatio BETWEEN 0 AND 0.5 THEN 'Low Answer Rate'
    WHEN uam.AnswerToQuestionRatio BETWEEN 0.5 AND 2 THEN 'Balanced'
    WHEN uam.AnswerToQuestionRatio > 2 THEN 'High Answer Rate'
    ELSE 'No Answers'
  END AS AnswerProfile
FROM
  UserActivityMetrics AS uam
WHERE
  uam.DaysSinceCreation > 3650
  AND uam.Reputation > 10000;
