WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate AS PostCreationDate,
    p.AnswerCount,
    p.FavoriteCount,
    p.Score,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
    LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
    LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
    SUM(c.Score) OVER (PARTITION BY p.OwnerUserId) AS TotalCommentScoreForUser,
    p.PostTypeId,
    p.CreationDate
  FROM Posts p
  JOIN Users u
    ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  WHERE
    p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserPostStats AS (
  SELECT
    OwnerUserId,
    COUNT(Id) AS TotalPosts,
    AVG(Score) AS AverageScore,
    SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts,
    SUM(CASE WHEN Score < 0 THEN 1 ELSE 0 END) AS NegativeScorePosts,
    MAX(CreationDate) AS LastPostDate,
    MIN(CreationDate) AS FirstPostDate
  FROM Posts
  WHERE
    OwnerUserId IS NOT NULL AND OwnerUserId <> -1
  GROUP BY
    OwnerUserId
)
SELECT
  rp.PostId,
  rp.Title,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.OwnerReputation,
  rp.PostCreationDate,
  rp.AnswerCount,
  rp.FavoriteCount,
  COALESCE(rp.TotalCommentScoreForUser, 0) AS TotalCommentScoreForUser,
  rp.PreviousPostScore,
  rp.NextPostScore,
  (rp.NextPostScore - rp.PreviousPostScore) AS ScoreDifference,
  CASE
    WHEN rp.Score > 0 AND rp.NextPostScore > rp.PreviousPostScore THEN 'Gaining Momentum'
    WHEN rp.Score < 0 AND rp.NextPostScore < rp.PreviousPostScore THEN 'Losing Traction'
    WHEN rp.Score = 0 THEN 'Neutral'
    ELSE 'Stable'
  END AS PostTrend,
  COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
  COALESCE(ups.AverageScore, 0.0) AS UserAverageScore,
  COALESCE(ups.QuestionCount, 0) AS UserQuestionCount,
  COALESCE(ups.AnswerCount, 0) AS UserAnswerCount,
  COALESCE(ups.PositiveScorePosts, 0) AS UserPositiveScorePosts,
  COALESCE(ups.NegativeScorePosts, 0) AS UserNegativeScorePosts,
  ups.LastPostDate,
  ups.FirstPostDate,
  CAST(
    -- standard SQL date difference in days: (last - first) as integer number of days
    EXTRACT(EPOCH FROM (ups.LastPostDate - ups.FirstPostDate)) / 86400.0
    AS INTEGER
  ) AS UserPostActiveDays,
  CASE
    WHEN rp.rn <= 5 THEN 'Top 5 Recent'
    WHEN rp.rn > 5 AND rp.rn <= 20 THEN 'Next 15 Recent'
    ELSE 'Older Posts'
  END AS RecencyRank,
  CASE
    WHEN rp.FavoriteCount > 100 AND rp.Score > 50 THEN 'Highly Favorited & Scored'
    WHEN rp.AnswerCount > 10 THEN 'High Answer Volume'
    ELSE 'Standard'
  END AS PostPopularity,
  CASE
    WHEN rp.OwnerReputation > 100000 AND rp.PostCreationDate < DATE '2015-01-01' THEN 'Established Expert Old Post'
    WHEN rp.OwnerReputation < 5000 THEN 'Newer User Post'
    ELSE 'Mid-Tier User Post'
  END AS UserExperienceTier,
  (rp.NextPostScore + rp.PreviousPostScore) AS SymmetricScoreInfluence,
  (rp.OwnerDisplayName || ' (' || rp.OwnerReputation || ')') AS OwnerInfo,
  CASE WHEN rp.Title LIKE '%[jQuery]%' THEN 'jQuery Related' ELSE 'Other' END AS TitleTagIndicator,
  CASE
    WHEN rp.PostCreationDate >= cast('2024-10-01' as date) - INTERVAL '7 day' THEN 'This Week'
    WHEN rp.PostCreationDate >= cast('2024-10-01' as date) - INTERVAL '30 day' THEN 'This Month'
    ELSE 'Older Than Month'
  END AS PostAgeGroup
FROM RankedPosts rp
LEFT JOIN UserPostStats ups
  ON rp.OwnerUserId = ups.OwnerUserId
WHERE
  rp.rn <= 10

UNION ALL

SELECT
  NULL AS PostId,
  '--- Total Stats ---' AS Title,
  NULL AS OwnerUserId,
  NULL AS OwnerDisplayName,
  NULL AS OwnerReputation,
  NULL AS PostCreationDate,
  COUNT(p.Id) AS AnswerCount,
  NULL AS FavoriteCount,
  NULL AS TotalCommentScoreForUser,
  NULL AS PreviousPostScore,
  NULL AS NextPostScore,
  NULL AS ScoreDifference,
  NULL AS PostTrend,
  NULL AS UserTotalPosts,
  NULL AS UserAverageScore,
  NULL AS UserQuestionCount,
  NULL AS UserAnswerCount,
  NULL AS UserPositiveScorePosts,
  NULL AS UserNegativeScorePosts,
  NULL AS LastPostDate,
  NULL AS FirstPostDate,
  NULL AS UserPostActiveDays,
  NULL AS RecencyRank,
  NULL AS PostPopularity,
  NULL AS UserExperienceTier,
  NULL AS SymmetricScoreInfluence,
  NULL AS OwnerInfo,
  NULL AS TitleTagIndicator,
  NULL AS PostAgeGroup
FROM Posts p
WHERE
  p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1;