-- {"query": "4908.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1438} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.AcceptedAnswerId,
      p.ParentId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
      CASE WHEN p.Title IS NOT NULL THEN LENGTH(p.Title) ELSE 0 END AS TitleLength,
      CASE WHEN p.Tags IS NOT NULL THEN LENGTH(p.Tags) ELSE 0 END AS TagsLength,
      UPPER(SUBSTRING(COALESCE(u.DisplayName, 'Anonymous'), 1, 3)) AS UserDisplayNamePrefix,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountOnPost,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) OVER (PARTITION BY p.PostTypeId) AS AvgPostScoreByType
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2) -- Questions and Answers
  ),
  UserPostStats AS (
    SELECT
      OwnerUserId,
      COUNT(PostId) AS TotalPosts,
      SUM(PostScore) AS TotalScore,
      AVG(CAST(PostViewCount AS DECIMAL(10, 2))) AS AvgViewCount,
      MAX(PostCreationDate) AS LatestPostDate,
      COUNT(CASE WHEN PostTypeId = 1 THEN PostId ELSE NULL END) AS QuestionCount,
      COUNT(CASE WHEN PostTypeId = 2 THEN PostId ELSE NULL END) AS AnswerCount
    FROM RankedPosts
    WHERE
      PostRank <= 10 -- Consider only the top 10 posts per user
    GROUP BY
      OwnerUserId
  ),
  RecentActivity AS (
    SELECT DISTINCT
      ph.UserId,
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate AS ActivityDate,
      ROW_NUMBER() OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS ActivityRank
    FROM PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (2, 5, 4, 6) -- Edits and Initial Content
  )
SELECT
  rp.PostId,
  rp.PostTypeId,
  rp.PostCreationDate,
  rp.PostScore,
  rp.PostViewCount,
  rp.AnswerCount AS PostAnswerCount,
  rp.CommentCountOnPost,
  rp.FavoriteCount,
  rp.UserDisplayNamePrefix,
  COALESCE(u.Reputation, 0) AS UserReputation,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN rp.PostScore > 50 THEN 'High Score'
    WHEN rp.PostViewCount > 10000 THEN 'High View Count'
    ELSE 'Standard'
  END AS PostStatusCategory,
  CASE
    WHEN rp.PostTypeId = 1 THEN COALESCE(rp.AvgPostScoreByType, 0)
    ELSE 0
  END AS AvgQuestionScore,
  CASE
    WHEN rp.PostTypeId = 2 THEN COALESCE(rp.AvgPostScoreByType, 0)
    ELSE 0
  END AS AvgAnswerScore,
  COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
  COALESCE(ups.TotalScore, 0) AS UserTotalScore,
  COALESCE(ups.AvgViewCount, 0.0) AS UserAvgViewCount,
  COALESCE(ups.QuestionCount, 0) AS UserQuestionCount,
  COALESCE(ups.AnswerCount, 0) AS UserAnswerCount,
  DATEDIFF(
    DAY,
    u.CreationDate,
    GETDATE()
  ) AS UserAgeDays,
  CASE
    WHEN ra.ActivityRank <= 5 THEN 'Recent High Activity'
    ELSE 'Standard Activity'
  END AS UserActivityLevel,
  CONCAT(
    'Tags: ',
    COALESCE(rp.Tags, 'None')
  ) AS FormattedTags,
  CASE
    WHEN rp.ParentId IS NOT NULL THEN (
      SELECT
        COUNT(*)
      FROM Comments AS c_sub
      WHERE
        c_sub.PostId = rp.Id AND c_sub.Score > 5
    )
    ELSE 0
  END AS AnswerCommentsScoreAbove5,
  (
    SELECT
      SUM(COALESCE(CAST(v.VoteTypeId AS BIGINT), 0))
    FROM Votes AS v
    WHERE
      v.PostId = rp.Id
  ) AS TotalVoteTypeSum,
  (
    SELECT
      MIN(rp_sub.PostCreationDate)
    FROM RankedPosts AS rp_sub
    WHERE
      rp_sub.OwnerUserId = rp.OwnerUserId
      AND rp_sub.PostTypeId = 1 -- Only consider questions for min creation date
  ) AS UserFirstQuestionDate,
  rp.PostRank AS UserPostRank
FROM RankedPosts AS rp
LEFT JOIN Users AS u
  ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostStats AS ups
  ON rp.OwnerUserId = ups.OwnerUserId
LEFT JOIN RecentActivity AS ra
  ON rp.OwnerUserId = ra.UserId AND ra.ActivityRank = 1
WHERE
  rp.PostRank <= 5 -- Top 5 posts per user based on creation date
  AND u.Reputation > 1000
  AND rp.PostScore >= 0
  AND (
    rp.ClosedDate IS NULL
    OR rp.ClosedDate > DATEADD(month, -6, GETDATE())
  )
ORDER BY
  rp.PostCreationDate DESC,
  rp.PostScore DESC
LIMIT 100;
