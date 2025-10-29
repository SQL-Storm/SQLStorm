-- {"query": "4427.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1640}
WITH
  UserPostInteraction AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LatestPostDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeCount AS (
    SELECT
      UserId,
      COUNT(*) AS BadgeCount,
      MAX(CASE WHEN Class = 1 THEN Date ELSE NULL END) AS GoldBadgeDate,
      MAX(CASE WHEN Class = 2 THEN Date ELSE NULL END) AS SilverBadgeDate,
      MAX(CASE WHEN Class = 3 THEN Date ELSE NULL END) AS BronzeBadgeDate
    FROM Badges
    GROUP BY
      UserId
  ),
  RecentActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      COALESCE(up.PostCount, 0) AS TotalPosts,
      COALESCE(up.QuestionCount, 0) AS TotalQuestions,
      COALESCE(up.AnswerCount, 0) AS TotalAnswers,
      COALESCE(up.AvgScore, 0.0) AS AveragePostScore,
      COALESCE(ub.BadgeCount, 0) AS TotalBadges,
      COALESCE(ub.GoldBadgeDate, DATE '1900-01-01') AS LastGoldBadge,
      COALESCE(ub.SilverBadgeDate, DATE '1900-01-01') AS LastSilverBadge,
      COALESCE(ub.BronzeBadgeDate, DATE '1900-01-01') AS LastBronzeBadge,
      CASE
        WHEN up.LatestPostDate IS NOT NULL AND up.LatestPostDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY) THEN 'Active Recently'
        WHEN up.LatestPostDate IS NOT NULL AND up.LatestPostDate >= (CAST('2024-10-01' AS date) - INTERVAL '90' DAY) THEN 'Moderately Active'
        ELSE 'Inactive'
      END AS ActivityLevel,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'StackOverflow User'
        WHEN u.WebsiteUrl IS NOT NULL THEN 'External User'
        ELSE 'No Website'
      END AS WebsiteType,
      (
        EXTRACT(EPOCH FROM (COALESCE(u.LastAccessDate, CAST('2024-10-01 12:34:56' AS timestamp)) - COALESCE(u.CreationDate, CAST('2024-10-01 12:34:56' AS timestamp)))) / 60.0 / 60.0 / 24.0 / 365.25
      ) AS AccountAgeInYears,
      CASE
        WHEN LENGTH(TRIM(COALESCE(u.AboutMe, ''))) > 100 THEN 'Detailed Bio'
        WHEN LENGTH(TRIM(COALESCE(u.AboutMe, ''))) > 0 THEN 'Brief Bio'
        ELSE 'No Bio'
      END AS BioLengthCategory
    FROM Users AS u
    LEFT JOIN UserPostInteraction AS up
      ON u.Id = up.OwnerUserId
    LEFT JOIN UserBadgeCount AS ub
      ON u.Id = ub.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      up.PostCount,
      up.QuestionCount,
      up.AnswerCount,
      up.AvgScore,
      up.LatestPostDate,
      ub.BadgeCount,
      ub.GoldBadgeDate,
      ub.SilverBadgeDate,
      ub.BronzeBadgeDate,
      u.WebsiteUrl,
      u.LastAccessDate,
      u.AboutMe
  )
SELECT
  ra.DisplayName,
  ra.Reputation,
  ra.TotalPosts,
  ra.TotalQuestions,
  ra.TotalAnswers,
  ra.AveragePostScore,
  ra.TotalBadges,
  ra.LastGoldBadge,
  ra.LastSilverBadge,
  ra.LastBronzeBadge,
  ra.ActivityLevel,
  ra.WebsiteType,
  ra.AccountAgeInYears,
  ra.BioLengthCategory,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.UserId = ra.UserId AND c.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '365' DAY)
  ) AS CommentsLastYear,
  (
    SELECT
      COUNT(DISTINCT ph.PostId)
    FROM PostHistory AS ph
    WHERE
      ph.UserId = ra.UserId AND ph.PostHistoryTypeId IN (4, 5, 6) AND ph.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '180' DAY)
  ) AS EditsLastSixMonths,
  CASE
    WHEN (
      SELECT
        COUNT(*)
      FROM Votes AS v
      WHERE
        v.UserId = ra.UserId AND v.VoteTypeId = 2 AND v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    ) > (
      SELECT
        COUNT(*)
      FROM Votes AS v
      WHERE
        v.UserId = ra.UserId AND v.VoteTypeId = 3 AND v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    ) THEN 'Net Positive Votes'
    WHEN (
      SELECT
        COUNT(*)
      FROM Votes AS v
      WHERE
        v.UserId = ra.UserId AND v.VoteTypeId = 2 AND v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    ) < (
      SELECT
        COUNT(*)
      FROM Votes AS v
      WHERE
        v.UserId = ra.UserId AND v.VoteTypeId = 3 AND v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    ) THEN 'Net Negative Votes'
    ELSE 'Neutral Votes'
  END AS LastMonthVoteBalance,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Posts AS p
      WHERE
        p.OwnerUserId = ra.UserId AND p.ClosedDate IS NOT NULL
    ) THEN 'Has Closed Posts'
    ELSE 'No Closed Posts'
  END AS PostClosureStatus,
  (
    SELECT
      COUNT(DISTINCT pl.PostId)
    FROM PostLinks AS pl
    JOIN Posts AS p
      ON pl.PostId = p.Id
    WHERE
      p.OwnerUserId = ra.UserId AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  (
    SELECT
      SUM(p.FavoriteCount)
    FROM Posts AS p
    WHERE
      p.OwnerUserId = ra.UserId AND p.PostTypeId = 1
  ) AS TotalQuestionFavorites,
  CASE
    WHEN ra.AveragePostScore > 100 THEN 'High Performer'
    WHEN ra.AveragePostScore > 20 THEN 'Solid Contributor'
    ELSE 'Developing Contributor'
  END AS ScoreCategory,
  COALESCE(
    (
      SELECT
        STRING_AGG(b.Name, '; ' ORDER BY b.Date DESC)
      FROM Badges AS b
      WHERE
        b.UserId = ra.UserId AND b.Class = 1
      LIMIT 3
    ),
    'No Top Gold Badges'
  ) AS TopGoldBadges
FROM RecentActivity AS ra
WHERE
  ra.Reputation > 1000 AND ra.TotalPosts > 50
GROUP BY
  ra.UserId,
  ra.DisplayName,
  ra.Reputation,
  ra.TotalPosts,
  ra.TotalQuestions,
  ra.TotalAnswers,
  ra.AveragePostScore,
  ra.TotalBadges,
  ra.LastGoldBadge,
  ra.LastSilverBadge,
  ra.LastBronzeBadge,
  ra.ActivityLevel,
  ra.WebsiteType,
  ra.AccountAgeInYears,
  ra.BioLengthCategory
ORDER BY
  ra.Reputation DESC,
  ra.TotalPosts DESC
LIMIT 100;