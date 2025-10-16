-- {"query": "2031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 559} 

WITH UserActivitySummary AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        IFNULL(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        IFNULL(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        IFNULL(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        IFNULL(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        IFNULL(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COALESCE(U.Reputation, 0) / NULLIF(DATEDIFF(NOW(), U.CreationDate), 0) AS AvgReputationPerDay
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING 
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) > 0
),
TopContributors AS (
    SELECT 
        UserId, 
        DisplayName,
        AVG(Score) OVER (PARTITION BY UserId) AS AvgPostScore,
        Ranking
    FROM (
        SELECT 
            UAS.UserId, 
            UAS.DisplayName, 
            P.Score,
            ROW_NUMBER() OVER (ORDER BY COALESCE(UAS.AvgReputationPerDay, 0) DESC) AS Ranking
        FROM 
            UserActivitySummary UAS
        LEFT JOIN 
            Posts P ON UAS.UserId = P.OwnerUserId
        WHERE 
            P.Score > 0
    ) AS RankedData
    WHERE 
        Ranking <= 10
)
SELECT 
    TC.DisplayName,
    P.Title AS TopQuestionTitle, 
    STRING_AGG(TC.TagName, ', ') AS AssociatedTags
FROM 
    TopContributors TC
INNER JOIN 
    Posts P ON TC.UserId = P.OwnerUserId AND P.PostTypeId = 1
LEFT JOIN 
    Tags T ON POSITION('<' || T.TagName || '>' IN P.Tags) > 0
GROUP BY 
    TC.DisplayName, P.Title
ORDER BY 
    AVG(TC.AvgPostScore) DESC, COUNT(P.Id) DESC;
