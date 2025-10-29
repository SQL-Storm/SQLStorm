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
      CASE WHEN p.Title IS NOT NULL THEN CHAR_LENGTH(p.Title) ELSE 0 END AS TitleLength,
      CASE WHEN p.Tags IS NOT NULL THEN CHAR_LENGTH(p.Tags) ELSE 0 END AS TagsLength,
      UPPER(SUBSTRING(COALESCE(u.DisplayName, 'Anonymous') FROM 1 FOR 3)) AS UserDisplayNamePrefix,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountOnPost,
      AVG(CAST(p.Score AS NUMERIC(10, 2))) OVER (PARTITION BY p.PostTypeId) AS AvgPostScoreByType,
      p.Tags
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
  ),
  UserPostStats AS (
    SELECT
      OwnerUserId,
      COUNT(PostId) AS TotalPosts,
      SUM(PostScore) AS TotalScore,
      AVG(CAST(PostViewCount AS NUMERIC(10, 2))) AS AvgViewCount,
      MAX(PostCreationDate) AS LatestPostDate,
      COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCount,
      COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM RankedPosts
    WHERE
      PostRank <= 10
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
    FROM PostHistory ph
    WHERE
      ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (2, 5, 4, 6)
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
  CAST((EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400) AS INTEGER) AS UserAgeDays,
  CASE
    WHEN ra.ActivityRank <= 5 THEN 'Recent High Activity'
    ELSE 'Standard Activity'
  END AS UserActivityLevel,
  ('Tags: ' || COALESCE(rp.Tags, 'None')) AS FormattedTags,
  CASE
    WHEN rp.ParentId IS NOT NULL THEN (
      SELECT
        COUNT(*)
      FROM Comments c_sub
      WHERE
        c_sub.PostId = rp.PostId AND c_sub.Score > 5
    )
    ELSE 0
  END AS AnswerCommentsScoreAbove5,
  (
    SELECT
      SUM(COALESCE(CAST(v.VoteTypeId AS BIGINT), 0))
    FROM Votes v
    WHERE
      v.PostId = rp.PostId
  ) AS TotalVoteTypeSum,
  (
    SELECT
      MIN(rp_sub.PostCreationDate)
    FROM RankedPosts rp_sub
    WHERE
      rp_sub.OwnerUserId = rp.OwnerUserId
      AND rp_sub.PostTypeId = 1
  ) AS UserFirstQuestionDate,
  rp.PostRank AS UserPostRank
FROM RankedPosts rp
LEFT JOIN Users u
  ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostStats ups
  ON rp.OwnerUserId = ups.OwnerUserId
LEFT JOIN RecentActivity ra
  ON rp.OwnerUserId = ra.UserId AND ra.ActivityRank = 1
WHERE
  rp.PostRank <= 5
  AND COALESCE(u.Reputation, 0) > 1000
  AND rp.PostScore >= 0
  AND (
    rp.ClosedDate IS NULL
    OR rp.ClosedDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months')
  )
ORDER BY
  rp.PostCreationDate DESC,
  rp.PostScore DESC
LIMIT 100;