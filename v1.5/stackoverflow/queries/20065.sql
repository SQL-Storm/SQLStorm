WITH UserContributionSummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    EXTRACT(
      EPOCH
      FROM
        (u.LastAccessDate - u.CreationDate)
    ) / 86400.0 AS AccountAgeDays,
    COALESCE(PostCounts.QuestionCount, 0) AS QuestionCount,
    COALESCE(PostCounts.AnswerCount, 0) AS AnswerCount,
    COALESCE(CommentCounts.CommentCount, 0) AS CommentCount,
    COALESCE(BadgeCounts.GoldBadges, 0) AS GoldBadges,
    COALESCE(BadgeCounts.SilverBadges, 0) AS SilverBadges,
    COALESCE(BadgeCounts.BronzeBadges, 0) AS BronzeBadges
  FROM Users AS u
  LEFT JOIN (
    SELECT
      OwnerUserId,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ) AS PostCounts
    ON u.Id = PostCounts.OwnerUserId
  LEFT JOIN (
    SELECT
      UserId,
      COUNT(Id) AS CommentCount
    FROM Comments
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ) AS CommentCounts
    ON u.Id = CommentCounts.UserId
  LEFT JOIN (
    SELECT
      UserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY
      UserId
  ) AS BadgeCounts
    ON u.Id = BadgeCounts.UserId
), AnswerPerformance AS (
  SELECT
    a.OwnerUserId,
    AVG(a.Score) AS AvgAnswerScore,
    CAST(SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS REAL) / COUNT(a.Id) AS AcceptanceRate,
    AVG(
      EXTRACT(
        EPOCH
        FROM
          (a.CreationDate - q.CreationDate)
      )
    ) AS AvgTimeToAnswerSeconds
  FROM Posts AS a
  INNER JOIN Posts AS q
    ON a.ParentId = q.Id
  WHERE
    a.PostTypeId = 2 -- Answers
    AND a.OwnerUserId IS NOT NULL
  GROUP BY
    a.OwnerUserId
  HAVING
    COUNT(a.Id) > 10
), TagSpecialists AS (
  SELECT
    p.OwnerUserId,
    string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') AS TagsArray
  FROM Posts p
  WHERE
    p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
), TopUsersUnion AS (
  SELECT UserId FROM UserContributionSummary WHERE GoldBadges > 5
  UNION
  SELECT OwnerUserId FROM AnswerPerformance WHERE AcceptanceRate > 0.7 AND AvgAnswerScore > 20
)
SELECT
  ucs.DisplayName,
  ucs.Reputation,
  -- Complicated Scoring Expression
  (
    ucs.Reputation * 0.1 + ap.AvgAnswerScore * 5 + ap.AcceptanceRate * 100 + ucs.GoldBadges * 50 + ucs.SilverBadges * 25 + ucs.BronzeBadges * 5 - (
      CASE WHEN ap.AvgTimeToAnswerSeconds < 3600 THEN 0 ELSE ap.AvgTimeToAnswerSeconds / 3600 END
    )
  ) AS OverallPerformanceScore,
  -- Window Functions
  RANK() OVER (ORDER BY ucs.Reputation DESC) AS ReputationRank,
  NTILE(100) OVER (ORDER BY (
    ucs.Reputation * 0.1 + ap.AvgAnswerScore * 5 + ap.AcceptanceRate * 100 + ucs.GoldBadges * 50 + ucs.SilverBadges * 25 + ucs.BronzeBadges * 5
  ) DESC) AS PerformancePercentile,
  LAG(ucs.DisplayName, 1, 'Nobody') OVER (ORDER BY ucs.Reputation DESC) AS NextHighestRepUser,
  SUM(ucs.QuestionCount + ucs.AnswerCount) OVER (ORDER BY ucs.CreationDate) AS CumulativePosts,
  -- String and NULL Logic
  CONCAT(
    'User: ',
    ucs.DisplayName,
    ', Bio Length: ',
    COALESCE(
      CAST(LENGTH(u.AboutMe) AS VARCHAR),
      'N/A'
    )
  ) AS UserSummaryString,
  ap.AvgAnswerScore,
  ap.AcceptanceRate,
  -- Correlated Subquery
  (
    SELECT
      p.Title
    FROM Posts p
    WHERE
      p.OwnerUserId = ucs.UserId AND p.PostTypeId = 1
    ORDER BY
      p.Score DESC,
      p.ViewCount DESC
    LIMIT 1
  ) AS TopQuestionTitle
FROM UserContributionSummary ucs
INNER JOIN AnswerPerformance ap
  ON ucs.UserId = ap.OwnerUserId
INNER JOIN Users u
  ON ucs.UserId = u.Id
-- Filter to only include users from the UNION set
WHERE
  ucs.UserId IN (SELECT UserId FROM TopUsersUnion)
  -- Complex Predicate
  AND (
    ucs.AccountAgeDays > 365
    OR ucs.Reputation > (
      SELECT
        AVG(Reputation)
      FROM Users
    )
  )
  AND (
    SELECT
      COUNT(DISTINCT tag)
    FROM TagSpecialists ts,
      UNNEST(ts.TagsArray) AS unnest(tag)
    WHERE
      ts.OwnerUserId = ucs.UserId
  ) > 5
  AND u.Location IS NOT NULL
  AND u.AboutMe NOT LIKE '%inactive%'
ORDER BY
  OverallPerformanceScore DESC NULLS LAST
LIMIT 100;