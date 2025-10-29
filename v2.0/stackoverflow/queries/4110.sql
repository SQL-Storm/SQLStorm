WITH
  UserPostEngagement AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Posts p
    LEFT JOIN
      Comments c
      ON p.Id = c.PostId
    LEFT JOIN
      Votes v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeSummary AS (
    SELECT
      UserId,
      COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
      MAX(Date) AS LastBadgeDate
    FROM
      Badges
    GROUP BY
      UserId
  ),
  UserActivityRank AS (
    SELECT
      Id,
      Reputation,
      CreationDate,
      DisplayName,
      LastAccessDate,
      ROW_NUMBER() OVER (ORDER BY LastAccessDate DESC) AS ActivityRank,
      CASE
        WHEN Reputation BETWEEN 0 AND 1000 THEN 'Novice'
        WHEN Reputation BETWEEN 1001 AND 10000 THEN 'Experienced'
        WHEN Reputation > 10000 THEN 'Expert'
        ELSE 'Unknown'
      END AS ReputationLevel
    FROM
      Users
    WHERE
      Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1)
  )
SELECT
  uar.DisplayName,
  uar.Reputation,
  uar.ReputationLevel,
  uar.ActivityRank,
  COALESCE(upe.PostCount, 0) AS TotalQuestions,
  COALESCE(upe.CommentCount, 0) AS TotalComments,
  COALESCE(upe.UpVotesReceived, 0) AS TotalUpvotesOnQuestions,
  COALESCE(upe.DownVotesReceived, 0) AS TotalDownvotesOnQuestions,
  COALESCE(upe.AvgPostScore, 0) AS AverageQuestionScore,
  COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
  COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
  COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
  CASE
    WHEN uar.LastAccessDate > cast('2024-10-01' as date) - INTERVAL '30 day' THEN 'Active Recently'
    WHEN uar.LastAccessDate > cast('2024-10-01' as date) - INTERVAL '180 day' THEN 'Moderately Active'
    ELSE 'Lapsed'
  END AS ActivityStatus,
  CASE
    WHEN ubs.LastBadgeDate > cast('2024-10-01' as date) - INTERVAL '90 day' THEN 'Recently Awarded'
    WHEN ubs.LastBadgeDate IS NULL THEN 'No Badges'
    ELSE 'Inactive Badge Status'
  END AS BadgeActivity,
  UPPER(SUBSTRING(uar.DisplayName FROM 1 FOR 1)) || LOWER(SUBSTRING(uar.DisplayName FROM 2)) AS FormattedDisplayName
FROM
  UserActivityRank uar
LEFT JOIN
  UserPostEngagement upe
  ON uar.Id = upe.OwnerUserId
LEFT JOIN
  UserBadgeSummary ubs
  ON uar.Id = ubs.UserId
WHERE
  (
    COALESCE(upe.PostCount, 0) > 10
    OR COALESCE(ubs.GoldBadges, 0) > 0
  )
  AND uar.DisplayName ~ '^[A-Za-z0-9 ]+$'
  AND uar.CreationDate < cast('2024-10-01' as date) - INTERVAL '1 year'
GROUP BY
  uar.DisplayName,
  uar.Reputation,
  uar.ReputationLevel,
  uar.ActivityRank,
  uar.LastAccessDate,
  uar.CreationDate,
  uar.Id,
  upe.PostCount,
  upe.CommentCount,
  upe.UpVotesReceived,
  upe.DownVotesReceived,
  upe.AvgPostScore,
  upe.OwnerUserId,
  ubs.GoldBadges,
  ubs.SilverBadges,
  ubs.BronzeBadges,
  ubs.LastBadgeDate
ORDER BY
  uar.ActivityRank,
  uar.Reputation DESC
LIMIT 100;