-- {"query": "35003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 662} 
WITH TopUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(P.Score) AS TotalScore,
        RANK() OVER (ORDER BY SUM(P.Score) DESC) AS UserRank
    FROM Users U
    INNER JOIN Posts P ON P.OwnerUserId = U.Id
    WHERE U.CreationDate > NOW() - INTERVAL '3 years'
    GROUP BY U.Id, U.DisplayName
    HAVING SUM(P.Score) > 1000 AND SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) > 5
),
ActiveQuestions AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        Q.Score,
        Q.OwnerUserId,
        COUNT(A.Id) AS AnswerCount,
        MAX(A.Score) AS TopAnswerScore,
        MIN(A.CreationDate) AS FirstAnswerDate
    FROM Posts Q
    LEFT JOIN Posts A ON A.ParentId = Q.Id AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1 AND Q.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY Q.Id, Q.Title, Q.Score, Q.OwnerUserId
    HAVING COUNT(A.Id) >= 3 AND MAX(A.Score) > 5
),
BadgeSummary AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges B
    WHERE B.Date > NOW() - INTERVAL '3 years'
    GROUP BY B.UserId
)
SELECT
    TU.UserId,
    TU.DisplayName,
    TU.QuestionCount,
    TU.AnswerCount,
    TU.TotalScore,
    TU.UserRank,
    BA.GoldBadges,
    BA.SilverBadges,
    BA.BronzeBadges,
    BA.TotalBadges,
    COUNT(DISTINCT AQ.QuestionId) AS ActiveQuestionsInvolved,
    AVG(AQ.TopAnswerScore) AS AvgTopAnswerScore,
    MIN(AQ.FirstAnswerDate) AS EarliestFirstAnswer
FROM TopUsers TU
LEFT JOIN BadgeSummary BA ON TU.UserId = BA.UserId
LEFT JOIN ActiveQuestions AQ ON AQ.OwnerUserId = TU.UserId
GROUP BY
    TU.UserId,
    TU.DisplayName,
    TU.QuestionCount,
    TU.AnswerCount,
    TU.TotalScore,
    TU.UserRank,
    BA.GoldBadges,
    BA.SilverBadges,
    BA.BronzeBadges,
    BA.TotalBadges
ORDER BY
    TU.UserRank ASC,
    ActiveQuestionsInvolved DESC
LIMIT 20;