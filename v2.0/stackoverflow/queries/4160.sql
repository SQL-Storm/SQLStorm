-- {"query": "4160.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1788}
WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AvgViewCount,
      MAX(p.CreationDate) AS LastPostDate,
      SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostCount,
      SUM(CASE WHEN p.FavoriteCount > 0 THEN 1 ELSE 0 END) AS FavoritedPostCount,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1 ELSE 0 END) AS InitialEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS SubsequentEdits
    FROM
      Posts p
      LEFT JOIN PostHistory ph
        ON p.Id = ph.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserVoteSummary AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesGiven,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesGiven,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS FavoritesGiven,
      SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedAnswers,
      SUM(CASE WHEN vt.Name = 'BountyStart' THEN 1 ELSE 0 END) AS BountyStarts
    FROM
      Votes v
      JOIN VoteTypes vt
        ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  UserBadgeStats AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
      MAX(b.Date) AS LastBadgeDate
    FROM
      Badges b
    GROUP BY
      b.UserId
  ),
  UserContributionScore AS (
    SELECT
      u.Id AS OwnerUserId,
      COALESCE(upa.PostCount, 0) AS TotalPosts,
      COALESCE(upa.QuestionCount, 0) AS TotalQuestions,
      COALESCE(upa.AnswerCount, 0) AS TotalAnswers,
      COALESCE(upa.TotalScore, 0) AS TotalScoreReceived,
      COALESCE(uvs.UpVotesGiven, 0) AS TotalUpVotesGiven,
      COALESCE(uvs.DownVotesGiven, 0) AS TotalDownVotesGiven,
      COALESCE(uvs.FavoritesGiven, 0) AS TotalFavoritesGiven,
      COALESCE(uvs.AcceptedAnswers, 0) AS TotalAcceptedAnswers,
      COALESCE(uvs.BountyStarts, 0) AS TotalBountyStarts,
      COALESCE(ubs.GoldBadges, 0) AS TotalGoldBadges,
      COALESCE(ubs.SilverBadges, 0) AS TotalSilverBadges,
      COALESCE(ubs.BronzeBadges, 0) AS TotalBronzeBadges,
      CASE
        WHEN COALESCE(upa.PostCount, 0) > 1000 THEN 'Prolific'
        WHEN COALESCE(upa.PostCount, 0) > 100 THEN 'Active'
        WHEN COALESCE(upa.PostCount, 0) > 10 THEN 'Regular'
        ELSE 'New'
      END AS ActivityLevel,
      CAST(
        EXTRACT(EPOCH FROM (COALESCE(ups.LastPostDate, u.CreationDate) - u.CreationDate)) / 86400
        AS INTEGER
      ) AS DaysSinceFirstPost,
      CAST(
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400
        AS INTEGER
      ) AS DaysSinceRegistration,
      (
        COALESCE(upa.TotalScore, 0) * 1.5
      ) + (
        COALESCE(uvs.UpVotesGiven, 0) * 0.5
      ) + (
        COALESCE(ubs.GoldBadges, 0) * 10
      ) + (
        COALESCE(ubs.SilverBadges, 0) * 5
      ) + (
        COALESCE(ubs.BronzeBadges, 0) * 2
      ) AS CompositeScore
    FROM
      Users u
      LEFT JOIN UserPostActivity upa
        ON u.Id = upa.OwnerUserId
      LEFT JOIN UserVoteSummary uvs
        ON u.Id = uvs.UserId
      LEFT JOIN UserBadgeStats ubs
        ON u.Id = ubs.UserId
      LEFT JOIN (
        SELECT
          OwnerUserId,
          MAX(CreationDate) AS LastPostDate
        FROM
          Posts
        GROUP BY
          OwnerUserId
      ) ups
        ON u.Id = ups.OwnerUserId
  )
SELECT
  u.DisplayName,
  ucs.TotalPosts,
  ucs.TotalQuestions,
  ucs.TotalAnswers,
  ucs.TotalScoreReceived,
  ucs.TotalUpVotesGiven,
  ucs.TotalDownVotesGiven,
  ucs.TotalFavoritesGiven,
  ucs.TotalAcceptedAnswers,
  ucs.TotalBountyStarts,
  ucs.TotalGoldBadges,
  ucs.TotalSilverBadges,
  ucs.TotalBronzeBadges,
  ucs.ActivityLevel,
  ucs.DaysSinceFirstPost,
  ucs.DaysSinceRegistration,
  ucs.CompositeScore,
  CASE
    WHEN ucs.CompositeScore > 5000 THEN 'Expert'
    WHEN ucs.CompositeScore > 1000 THEN 'Experienced'
    WHEN ucs.CompositeScore > 500 THEN 'Intermediate'
    ELSE 'Novice'
  END AS ExpertiseLevel,
  TRIM(BOTH FROM REPLACE(REPLACE(REPLACE(COALESCE(u.AboutMe, ''), '<p>', ''), '</p>', ''), '<br>', ' ')) AS SanitizedAboutMe,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Meta Stack Overflow'
    ELSE 'External Website'
  END AS WebsiteCategory,
  CASE
    WHEN u.Location LIKE '%USA%' THEN 'United States'
    WHEN u.Location LIKE '%Canada%' THEN 'Canada'
    WHEN u.Location LIKE '%United Kingdom%' THEN 'United Kingdom'
    ELSE 'Other'
  END AS CountryCategory,
  CASE
    WHEN u.Views IS NULL THEN 0
    WHEN u.Views > 100000 THEN u.Views / 100000
    ELSE 0
  END AS HundredKViewBuckets
FROM
  Users u
JOIN UserContributionScore ucs
  ON u.Id = ucs.OwnerUserId
WHERE
  ucs.TotalPosts > 5
  AND u.Id NOT IN (
    SELECT
      UserId
    FROM
      Badges
    WHERE
      Name LIKE '%Tagger%'
  )
  AND ucs.DaysSinceRegistration > 365
ORDER BY
  ucs.CompositeScore DESC,
  u.Reputation DESC
LIMIT 1000;