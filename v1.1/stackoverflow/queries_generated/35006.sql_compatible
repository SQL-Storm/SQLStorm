WITH TopUsers AS (
    SELECT U.Id AS UserId, U.DisplayName, U.Reputation, COUNT(P.Id) AS PostCount, SUM(P.Score) AS TotalScore
    FROM Users U
    JOIN Posts P ON P.OwnerUserId = U.Id
    WHERE P.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
      AND P.PostTypeId IN (1,2)
    GROUP BY U.Id, U.DisplayName, U.Reputation
    HAVING COUNT(P.Id) > 50
),
UserBadges AS (
    SELECT B.UserId, COUNT(*) AS BadgeCount, SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges B
    WHERE B.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY B.UserId
),
ActivePosts AS (
    SELECT P.Id AS PostId, P.OwnerUserId, P.Score, P.ViewCount, P.AnswerCount
    FROM Posts P
    WHERE P.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
      AND P.PostTypeId = 1
      AND P.ViewCount > 1000
      AND P.AnswerCount > 3
),
HotTags AS (
    SELECT T.TagName, SUM(P.ViewCount) AS TotalViews, COUNT(*) AS QuestionCount
    FROM Posts P
    JOIN LATERAL unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS tag(TagName) ON TRUE
    JOIN Tags T ON T.TagName = tag.TagName
    WHERE P.PostTypeId = 1
      AND P.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY T.TagName
    HAVING COUNT(*) > 100
    ORDER BY TotalViews DESC
    LIMIT 10
)
SELECT 
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.PostCount,
    TU.TotalScore,
    COALESCE(UB.BadgeCount, 0) AS BadgeCount,
    COALESCE(UB.GoldBadges, 0) AS GoldBadges,
    COUNT(DISTINCT AP.PostId) AS HotQuestionCount,
    AVG(AP.Score) AS AvgHotQuestionScore,
    SUM(AP.ViewCount) AS SumHotQuestionViews,
    COUNT(DISTINCT PV.Id) AS TotalUpvotesOnHot,
    ARRAY_AGG(DISTINCT HT.TagName) FILTER (WHERE HT.TagName IS NOT NULL) AS FrequentHotTags
FROM TopUsers TU
LEFT JOIN UserBadges UB ON UB.UserId = TU.UserId
LEFT JOIN ActivePosts AP ON AP.OwnerUserId = TU.UserId
LEFT JOIN Votes PV ON PV.PostId = AP.PostId AND PV.VoteTypeId = 2
LEFT JOIN LATERAL (
    SELECT tag.TagName
    FROM Posts p2
    JOIN LATERAL unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) AS tag(TagName) ON TRUE
    JOIN HotTags HT ON HT.TagName = tag.TagName
    WHERE p2.OwnerUserId = TU.UserId
      AND p2.PostTypeId = 1
      AND p2.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    LIMIT 5
) AS HT ON TRUE
GROUP BY TU.UserId, TU.DisplayName, TU.Reputation, TU.PostCount, TU.TotalScore, UB.BadgeCount, UB.GoldBadges
ORDER BY TU.TotalScore DESC
LIMIT 20;