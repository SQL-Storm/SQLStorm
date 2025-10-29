-- {"query": "4663.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1506} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts AS p
    WHERE
      p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
  ),
  UserPostActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(rp.PostId) AS TotalPosts,
      SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(rp.PostScore) AS AveragePostScore,
      MAX(rp.PostCreationDate) AS LatestPostDate,
      COUNT(CASE WHEN rp.ClosedDate IS NOT NULL THEN rp.PostId ELSE NULL END) AS ClosedPostCount
    FROM Users AS u
    LEFT JOIN RankedPosts AS rp
      ON u.Id = rp.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostsWithTags,
      SUM(CASE WHEN p.Tags IS NOT NULL THEN 1 ELSE 0 END) AS TaggedPosts,
      SUM(CASE WHEN p.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END) AS SqlTaggedPosts,
      AVG(p.Score) AS AvgScoreWithTags
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  PostLagLeadDifference AS (
    SELECT
      rp.PostId,
      rp.PostTypeId,
      (rp.PostScore - rp.PreviousPostScore) AS ScoreDifferenceFromPrevious,
      (rp.PostScore - rp.NextPostScore) AS ScoreDifferenceFromNext,
      rp.PostViewCount,
      rp.PostViewCount * rp.PostScore AS WeightedViewScore
    FROM RankedPosts AS rp
    WHERE
      rp.rn > 1 AND rp.rn < (
        SELECT
          COUNT(*)
        FROM RankedPosts AS rp2
        WHERE
          rp2.PostTypeId = rp.PostTypeId
      )
  ),
  UserMetrics AS (
    SELECT
      upa.UserId,
      upa.DisplayName,
      upa.TotalPosts,
      upa.QuestionCount,
      upa.AnswerCount,
      upa.AveragePostScore,
      upa.LatestPostDate,
      upa.ClosedPostCount,
      COALESCE(tc.TaggedPosts, 0) AS TotalTaggedPosts,
      COALESCE(tc.SqlTaggedPosts, 0) AS TotalSqlTaggedPosts,
      COALESCE(tc.AvgScoreWithTags, 0) AS AvgScoreForTaggedPosts,
      CASE
        WHEN upa.TotalPosts > 1000 THEN 'High Volume'
        WHEN upa.TotalPosts > 100 THEN 'Medium Volume'
        ELSE 'Low Volume'
      END AS VolumeCategory,
      CASE
        WHEN upa.AveragePostScore > 50 THEN 'High Score'
        WHEN upa.AveragePostScore > 10 THEN 'Medium Score'
        ELSE 'Low Score'
      END AS ScoreCategory
    FROM UserPostActivity AS upa
    LEFT JOIN TagContribution AS tc
      ON upa.UserId = tc.OwnerUserId
  )
SELECT
  um.UserId,
  um.DisplayName,
  um.TotalPosts,
  um.QuestionCount,
  um.AnswerCount,
  um.AveragePostScore,
  um.LatestPostDate,
  um.ClosedPostCount,
  um.TotalTaggedPosts,
  um.TotalSqlTaggedPosts,
  um.AvgScoreForTaggedPosts,
  um.VolumeCategory,
  um.ScoreCategory,
  pl.ScoreDifferenceFromPrevious,
  pl.ScoreDifferenceFromNext,
  pl.WeightedViewScore,
  CASE
    WHEN pl.WeightedViewScore > 100000 THEN 'High Impact'
    WHEN pl.WeightedViewScore > 10000 THEN 'Medium Impact'
    ELSE 'Low Impact'
  END AS ImpactCategory,
  CASE
    WHEN um.TotalPosts IS NULL THEN 'No Activity'
    WHEN um.TotalPosts > 0 AND um.ClosedPostCount / um.TotalPosts > 0.1 THEN 'High Closure Rate'
    ELSE 'Normal Closure Rate'
  END AS ClosureRateStatus,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.UserId = um.UserId AND c.Score > 5
  ) AS HighScoreCommentCount,
  (
    SELECT
      COUNT(b.Id)
    FROM Badges AS b
    WHERE
      b.UserId = um.UserId AND b.Class = 1
  ) AS GoldBadgeCount,
  CASE
    WHEN LENGTH(LTRIM(RTRIM(um.DisplayName))) = 0 THEN 'Anonymous'
    WHEN um.DisplayName LIKE '%[0-9]%' THEN 'HasDigits'
    ELSE 'CleanName'
  END AS DisplayNameType,
  COALESCE(CAST(um.AvgScoreForTaggedPosts AS VARCHAR), 'N/A') AS AvgScoreForTaggedPostsString
FROM UserMetrics AS um
LEFT JOIN PostLagLeadDifference AS pl
  ON um.UserId = (
    SELECT
      rp_inner.OwnerUserId
    FROM RankedPosts AS rp_inner
    WHERE
      rp_inner.Id = pl.PostId
  )
WHERE
  um.TotalPosts > 5 AND um.AveragePostScore > 0
ORDER BY
  um.TotalPosts DESC,
  um.AveragePostScore DESC
LIMIT 100;
