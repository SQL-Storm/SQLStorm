WITH UserYearlyActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    EXTRACT(YEAR FROM p.CreationDate) AS ActivityYear,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
    SUM(p.Score) AS TotalPostScore,
    SUM(p.ViewCount) AS TotalViewCount,
    SUM(p.FavoriteCount) AS TotalFavoriteCount,
    MIN(p.CreationDate) AS FirstActivityDate,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM
    Posts AS p
  WHERE
    p.OwnerUserId IS NOT NULL
    AND p.PostTypeId IN (1, 2)
  GROUP BY
    p.OwnerUserId,
    EXTRACT(YEAR FROM p.CreationDate)
), UserYearlyVotes AS (
  SELECT
    p.OwnerUserId AS UserId,
    EXTRACT(YEAR FROM v.CreationDate) AS ActivityYear,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
    SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) AS TotalBountyAmount
  FROM
    Votes AS v
    JOIN Posts AS p ON v.PostId = p.Id
  WHERE
    p.OwnerUserId IS NOT NULL
    AND v.VoteTypeId IN (2, 3, 8)
  GROUP BY
    p.OwnerUserId,
    EXTRACT(YEAR FROM v.CreationDate)
), UserYearlyBadges AS (
  SELECT
    b.UserId,
    EXTRACT(YEAR FROM b.Date) AS ActivityYear,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
  FROM
    Badges AS b
  WHERE
    b.UserId IS NOT NULL
  GROUP BY
    b.UserId,
    EXTRACT(YEAR FROM b.Date)
), CombinedStats AS (
  SELECT
    uya.UserId,
    u.DisplayName,
    u.Reputation,
    uya.ActivityYear,
    uya.QuestionsPosted,
    uya.AnswersPosted,
    uya.TotalPostScore,
    uya.TotalViewCount,
    uya.TotalFavoriteCount,
    uya.FirstActivityDate,
    uya.LastActivityDate,
    COALESCE(uyv.UpvotesReceived, 0) AS UpvotesReceived,
    COALESCE(uyv.DownvotesReceived, 0) AS DownvotesReceived,
    COALESCE(uyv.TotalBountyAmount, 0) AS TotalBountyAmount,
    COALESCE(uyb.GoldBadges, 0) AS GoldBadges,
    COALESCE(uyb.SilverBadges, 0) AS SilverBadges,
    COALESCE(uyb.BronzeBadges, 0) AS BronzeBadges,
    (
      (u.Reputation * 0.05) + (uya.TotalPostScore * 0.4) + (
        COALESCE(uyv.UpvotesReceived, 0) * 0.25
      ) - (
        COALESCE(uyv.DownvotesReceived, 0) * 0.1
      ) + (COALESCE(uyb.GoldBadges, 0) * 15) + (COALESCE(uyb.SilverBadges, 0) * 5) + (
        COALESCE(uyv.TotalBountyAmount, 0) * 0.01
      ) + (
        LOG(GREATEST(1, uya.TotalViewCount))
      ) + (uya.TotalFavoriteCount * 0.15)
    ) AS InfluenceScore
  FROM
    UserYearlyActivity AS uya
    JOIN Users AS u ON uya.UserId = u.Id
    LEFT JOIN UserYearlyVotes AS uyv ON uya.UserId = uyv.UserId
    AND uya.ActivityYear = uyv.ActivityYear
    LEFT JOIN UserYearlyBadges AS uyb ON uya.UserId = uyb.UserId
    AND uya.ActivityYear = uyb.ActivityYear
  WHERE
    u.Reputation > 1000
), RankedUsers AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY
        ActivityYear
      ORDER BY
        InfluenceScore DESC,
        Reputation DESC
    ) AS YearlyRank
  FROM
    CombinedStats
)
SELECT
  ru.ActivityYear,
  ru.YearlyRank,
  ru.DisplayName,
  ru.Reputation,
  CAST(ru.InfluenceScore AS INT) AS InfluenceScore,
  ru.TotalPostScore,
  ru.UpvotesReceived,
  ru.DownvotesReceived,
  ru.GoldBadges,
  ru.SilverBadges,
  ru.BronzeBadges,
  ru.QuestionsPosted,
  ru.AnswersPosted,
  (ru.AnswersPosted * 1.0) / NULLIF(ru.QuestionsPosted, 0) AS AnswerQuestionRatio,
  (
    SELECT
      AVG(c.Score)
    FROM
      Comments AS c
      JOIN Posts AS p ON c.PostId = p.Id
    WHERE
      p.OwnerUserId = ru.UserId
      AND EXTRACT(YEAR FROM p.CreationDate) = ru.ActivityYear
  ) AS AvgCommentScoreOnPosts,
  ru.FirstActivityDate,
  ru.LastActivityDate
FROM
  RankedUsers AS ru
WHERE
  ru.YearlyRank <= 10
ORDER BY
  ru.ActivityYear DESC,
  ru.YearlyRank ASC;