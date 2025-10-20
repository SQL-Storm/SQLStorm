WITH TopUsers AS (
  SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    COUNT(P.Id) AS TotalPosts,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions
  FROM
    Users U
    JOIN Posts P ON P.OwnerUserId = U.Id
  WHERE
    U.Reputation > 10000
  GROUP BY
    U.Id, U.DisplayName, U.Reputation
  HAVING
    COUNT(P.Id) > 50
),
FastestAnswerers AS (
  SELECT
    U.Id AS UserId,
    AVG(EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate))/60.0) AS AvgMinutesToAnswer
  FROM
    Users U
    JOIN Posts A ON A.OwnerUserId = U.Id AND A.PostTypeId = 2
    JOIN Posts Q ON A.ParentId = Q.Id AND Q.PostTypeId = 1
  WHERE
    U.Reputation > 10000
    AND A.CreationDate > Q.CreationDate
  GROUP BY
    U.Id
)
SELECT
  TU.UserId,
  TU.DisplayName,
  TU.Reputation,
  TU.TotalPosts,
  TU.Answers,
  TU.Questions,
  FA.AvgMinutesToAnswer,
  COALESCE(BadgeCounts.GoldBadges, 0) AS GoldBadges,
  COALESCE(BadgeCounts.SilverBadges, 0) AS SilverBadges,
  COALESCE(BadgeCounts.BronzeBadges, 0) AS BronzeBadges,
  V.UpVotes,
  V.DownVotes,
  ROUND(
    CAST(TU.Answers AS DECIMAL) / NULLIF(TU.Questions, 0), 2
  ) AS AnswerToQuestionRatio
FROM
  TopUsers TU
  LEFT JOIN FastestAnswerers FA ON TU.UserId = FA.UserId
  LEFT JOIN (
    SELECT
      B.UserId,
      SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
      Badges B
    GROUP BY
      B.UserId
  ) BadgeCounts ON TU.UserId = BadgeCounts.UserId
  LEFT JOIN (
    SELECT
      U.Id AS UserId,
      U.UpVotes,
      U.DownVotes
    FROM Users U
  ) V ON TU.UserId = V.UserId
GROUP BY
  TU.UserId,
  TU.DisplayName,
  TU.Reputation,
  TU.TotalPosts,
  TU.Answers,
  TU.Questions,
  FA.AvgMinutesToAnswer,
  BadgeCounts.GoldBadges,
  BadgeCounts.SilverBadges,
  BadgeCounts.BronzeBadges,
  V.UpVotes,
  V.DownVotes
ORDER BY
  TU.Reputation DESC,
  TU.Answers DESC
LIMIT 50;