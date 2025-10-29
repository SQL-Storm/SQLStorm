WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
      AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForType,
      COUNT(*) OVER (PARTITION BY p.PostTypeId) AS PostCountForType,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostScore,
      SUM(p.ViewCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViews
    FROM
      Posts p
      JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  ),
  UserPostStats AS (
    SELECT
      rp.OwnerUserId,
      rp.PostTypeId,
      COUNT(rp.PostId) AS NumberOfPosts,
      SUM(rp.PostScore) AS TotalScore,
      AVG(rp.PostScore) AS AverageScore,
      MAX(rp.PostScore) AS MaxScore,
      SUM(rp.PostViewCount) AS TotalViews,
      AVG(rp.PostViewCount) AS AverageViews,
      COUNT(CASE WHEN rp.PostTypeId = 1 THEN 1 END) AS QuestionCount,
      COUNT(CASE WHEN rp.PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM
      RankedPosts rp
    WHERE
      rp.OwnerUserId > 0
    GROUP BY
      rp.OwnerUserId,
      rp.PostTypeId
  ),
  TopUsers AS (
    SELECT
      ups.OwnerUserId,
      u.DisplayName,
      SUM(ups.NumberOfPosts) AS TotalPosts,
      SUM(ups.TotalScore) AS GrandTotalScore,
      SUM(ups.TotalViews) AS GrandTotalViews,
      MAX(ups.AverageScore) AS MaxAvgScoreAcrossTypes,
      SUM(ups.AnswerCount) AS TotalAnswers,
      SUM(ups.QuestionCount) AS TotalQuestions
    FROM
      UserPostStats ups
      JOIN Users u
      ON ups.OwnerUserId = u.Id
    WHERE
      ups.NumberOfPosts > 10
    GROUP BY
      ups.OwnerUserId,
      u.DisplayName
    ORDER BY
      GrandTotalScore DESC
    LIMIT 100
  )
SELECT
  tu.DisplayName,
  tu.TotalPosts,
  tu.GrandTotalScore,
  tu.GrandTotalViews,
  tu.MaxAvgScoreAcrossTypes,
  tu.TotalAnswers,
  tu.TotalQuestions,
  (
    SELECT
      COUNT(DISTINCT ph.PostId)
    FROM
      PostHistory ph
      JOIN RankedPosts rp ON ph.PostId = rp.PostId
    WHERE
      ph.PostHistoryTypeId = 5
      AND ph.UserId = tu.OwnerUserId
      AND rp.OwnerUserId = tu.OwnerUserId
      AND rp.PostTypeId = 1
      AND ph.CreationDate < rp.PostCreationDate + INTERVAL '7' DAY
  ) AS EditsToOwnQuestionsWithinWeek,
  CASE
    WHEN tu.TotalQuestions > 0 THEN CAST(tu.TotalAnswers AS NUMERIC) / tu.TotalQuestions
    ELSE 0.0
  END AS AvgAnswersPerQuestion,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = tu.OwnerUserId AND b.Name LIKE '%gold%' AND b.Class = 1
    ) THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS GoldBadgeStatus,
  COALESCE(u.Location, 'Unknown Location') AS UserLocation,
  COALESCE(u.WebsiteUrl, 'No Website') AS UserWebsite,
  CASE
    WHEN u.Views > 100000 THEN 'High Visitor'
    WHEN u.Views > 10000 THEN 'Medium Visitor'
    ELSE 'Low Visitor'
  END AS VisitorCategory,
  u.Reputation,
  u.DownVotes,
  u.UpVotes,
  (
    SELECT
      COUNT(DISTINCT p.Id)
    FROM
      Posts p
      LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE
      p.OwnerUserId = tu.OwnerUserId
      AND p.PostTypeId = 1
      AND c.Id IS NULL
  ) AS QuestionsWithoutComments,
  (
    SELECT
      SUM(rp.PostScore)
    FROM
      RankedPosts rp
    WHERE
      rp.OwnerUserId = tu.OwnerUserId
      AND rp.PostTypeId = 2
      AND rp.PostScore > (
        SELECT
          AVG(rp2.PostScore)
        FROM
          RankedPosts rp2
        WHERE
          rp2.OwnerUserId = tu.OwnerUserId
          AND rp2.PostTypeId = 2
      )
  ) AS ScoreOfAnswersAboveAverage,
  LOWER(SUBSTRING(tu.DisplayName FROM 1 FOR 3)) AS FirstThreeCharsOfDisplayName
FROM
  TopUsers tu
  JOIN Users u ON tu.OwnerUserId = u.Id
WHERE
  u.Reputation > 5000

UNION

SELECT
  tu.DisplayName,
  tu.TotalPosts,
  tu.GrandTotalScore,
  tu.GrandTotalViews,
  tu.MaxAvgScoreAcrossTypes,
  tu.TotalAnswers,
  tu.TotalQuestions,
  (
    SELECT
      COUNT(DISTINCT ph.PostId)
    FROM
      PostHistory ph
      JOIN RankedPosts rp ON ph.PostId = rp.PostId
    WHERE
      ph.PostHistoryTypeId = 5
      AND ph.UserId = tu.OwnerUserId
      AND rp.OwnerUserId = tu.OwnerUserId
      AND rp.PostTypeId = 1
      AND ph.CreationDate < rp.PostCreationDate + INTERVAL '7' DAY
  ) AS EditsToOwnQuestionsWithinWeek,
  CASE
    WHEN tu.TotalQuestions > 0 THEN CAST(tu.TotalAnswers AS NUMERIC) / tu.TotalQuestions
    ELSE 0.0
  END AS AvgAnswersPerQuestion,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = tu.OwnerUserId AND b.Name LIKE '%gold%' AND b.Class = 1
    ) THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS GoldBadgeStatus,
  COALESCE(u.Location, 'Unknown Location') AS UserLocation,
  COALESCE(u.WebsiteUrl, 'No Website') AS UserWebsite,
  CASE
    WHEN u.Views > 100000 THEN 'High Visitor'
    WHEN u.Views > 10000 THEN 'Medium Visitor'
    ELSE 'Low Visitor'
  END AS VisitorCategory,
  u.Reputation,
  u.DownVotes,
  u.UpVotes,
  (
    SELECT
      COUNT(DISTINCT p.Id)
    FROM
      Posts p
      LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE
      p.OwnerUserId = tu.OwnerUserId
      AND p.PostTypeId = 1
      AND c.Id IS NULL
  ) AS QuestionsWithoutComments,
  (
    SELECT
      SUM(rp.PostScore)
    FROM
      RankedPosts rp
    WHERE
      rp.OwnerUserId = tu.OwnerUserId
      AND rp.PostTypeId = 2
      AND rp.PostScore > (
        SELECT
          AVG(rp2.PostScore)
        FROM
          RankedPosts rp2
        WHERE
          rp2.OwnerUserId = tu.OwnerUserId
          AND rp2.PostTypeId = 2
      )
  ) AS ScoreOfAnswersAboveAverage,
  LOWER(SUBSTRING(tu.DisplayName FROM 1 FOR 3)) AS FirstThreeCharsOfDisplayName
FROM
  TopUsers tu
  JOIN Users u ON tu.OwnerUserId = u.Id
WHERE
  u.Reputation <= 5000;