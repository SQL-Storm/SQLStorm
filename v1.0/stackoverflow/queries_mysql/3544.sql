
WITH UserBadges AS (
    SELECT UserId, 
           COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
QuestionStats AS (
    SELECT P.OwnerUserId, 
           COUNT(DISTINCT P.Id) AS TotalQuestions, 
           SUM(P.AnswerCount) AS TotalAnswers,
           AVG(P.ViewCount) AS AvgViews,
           MAX(P.CreationDate) AS LastQuestionDate
    FROM Posts P
    WHERE P.PostTypeId = 1
    GROUP BY P.OwnerUserId 
),
PopularTags AS (
    SELECT SUBSTRING_INDEX(SUBSTRING_INDEX(T.Tags, '><', numbers.n), '><', -1) AS TagName, COUNT(*) AS TagCount
    FROM Posts T
    JOIN (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) numbers
    ON CHAR_LENGTH(T.Tags) - CHAR_LENGTH(REPLACE(T.Tags, '><', '')) >= numbers.n - 1
    WHERE T.PostTypeId = 1
    GROUP BY TagName
    ORDER BY TagCount DESC
    LIMIT 5
),
UserRanks AS (
    SELECT U.Id, U.DisplayName, U.Reputation,
           @rank := IF(@prev_reputation = U.Reputation, @rank, @rank + 1) AS ReputationRank,
           @prev_reputation := U.Reputation
    FROM Users U, (SELECT @rank := 0, @prev_reputation := NULL) r
    ORDER BY U.Reputation DESC
)
SELECT U.Id AS UserId, 
       U.DisplayName, 
       COALESCE(UB.GoldBadges, 0) AS GoldBadges,
       COALESCE(UB.SilverBadges, 0) AS SilverBadges,
       COALESCE(UB.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(Q.TotalQuestions, 0) AS TotalQuestions,
       COALESCE(Q.TotalAnswers, 0) AS TotalAnswers,
       COALESCE(Q.AvgViews, 0) AS AvgViews,
       U.ReputationRank,
       P.TagName
FROM UserRanks U
LEFT JOIN UserBadges UB ON U.Id = UB.UserId
LEFT JOIN QuestionStats Q ON U.Id = Q.OwnerUserId
LEFT JOIN PopularTags P ON 1=1
ORDER BY U.ReputationRank, U.DisplayName;
