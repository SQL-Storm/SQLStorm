WITH UserActivitySummary AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COALESCE(U.Reputation, 0) / NULLIF(DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate), 0) AS AvgReputationPerDay
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
    STRING_AGG(T.TagName, ', ') AS AssociatedTags
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