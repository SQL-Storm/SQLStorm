-- {"query": "4481.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1225} 

WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS Questions,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS Answers,
      AVG(p.Score) AS AvgScore,
      MAX(p.ViewCount) AS MaxViewCount,
      SUM(p.FavoriteCount) AS TotalFavorites
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeCounts AS (
    SELECT
      UserId,
      COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY
      UserId
  ),
  RecentActivity AS (
    SELECT
      UserId,
      MAX(CreationDate) AS LastActivityDate
    FROM (
      SELECT
        OwnerUserId AS UserId,
        CreationDate
      FROM Posts
      WHERE
        OwnerUserId IS NOT NULL AND OwnerUserId > 0
      UNION ALL
      SELECT
        UserId,
        CreationDate
      FROM Comments
      WHERE
        UserId IS NOT NULL AND UserId > 0
      UNION ALL
      SELECT
        UserId,
        CreationDate
      FROM Votes
      WHERE
        UserId IS NOT NULL
    ) AS AllActivity
    GROUP BY
      UserId
  ),
  TopTenUsers AS (
    SELECT
      UserId
    FROM UserPostStats
    ORDER BY
      TotalPosts DESC
    LIMIT 10
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COALESCE(ups.TotalPosts, 0) AS TotalPosts,
      COALESCE(ups.Questions, 0) AS Questions,
      COALESCE(ups.Answers, 0) AS Answers,
      COALESCE(ups.AvgScore, 0.0) AS AvgScore,
      COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
      COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
      COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
      ra.LastActivityDate,
      CASE
        WHEN u.Id IN (
          SELECT
            UserId
          FROM Votes
          WHERE
            VoteTypeId = 14
        ) THEN 'Nominated'
        ELSE 'Not Nominated'
      END AS ModeratorNominationStatus,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, ups.TotalPosts DESC) AS RankByReputation
    FROM Users AS u
    LEFT JOIN UserPostStats AS ups
      ON u.Id = ups.OwnerUserId
    LEFT JOIN UserBadgeCounts AS ubc
      ON u.Id = ubc.UserId
    LEFT JOIN RecentActivity AS ra
      ON u.Id = ra.UserId
    WHERE
      u.CreationDate < '2023-01-01'
      AND u.Id NOT IN (SELECT OwnerUserId FROM Posts WHERE OwnerUserId = -1)
  )
SELECT
  ue.UserId,
  ue.DisplayName,
  ue.Reputation,
  ue.TotalPosts,
  ue.Questions,
  ue.Answers,
  ue.AvgScore,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ue.LastActivityDate,
  ue.ModeratorNominationStatus,
  ue.RankByReputation,
  COALESCE(ps.MaxViewCount, 0) AS UserMaxPostViewCount,
  COALESCE(ps.TotalFavorites, 0) AS UserTotalPostFavorites,
  CASE
    WHEN ue.RankByReputation BETWEEN 1 AND 10 THEN 'Top 10'
    WHEN ue.RankByReputation BETWEEN 11 AND 100 THEN 'Top 100'
    ELSE 'Other'
  END AS ReputationTier,
  CASE
    WHEN ue.TotalPosts > 1000 AND ue.AvgScore > 10 THEN 'High Performer'
    WHEN ue.TotalPosts > 100 THEN 'Active Contributor'
    ELSE 'Standard Contributor'
  END AS ContributionLevel,
  SUBSTRING(ue.DisplayName, 1, 3) AS DisplayNamePrefix,
  UPPER(ue.DisplayName) AS DisplayNameUpper,
  CASE
    WHEN ue.LastActivityDate IS NULL OR ue.LastActivityDate < DATE('now', '-365 day') THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus
FROM UserEngagement AS ue
LEFT JOIN UserPostStats AS ps
  ON ue.UserId = ps.OwnerUserId
WHERE
  ue.Reputation > 10000 OR ue.TotalPosts > 500
ORDER BY
  ue.RankByReputation,
  ue.DisplayName;
