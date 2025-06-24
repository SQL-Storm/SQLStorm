
WITH UserBadges AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
PostAnalytics AS (
    SELECT 
        P.OwnerUserId,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN 1 END) AS QuestionsCount,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN 1 END) AS AnswersCount,
        SUM(IFNULL(P.Score, 0)) AS TotalScore,
        SUM(P.ViewCount) AS TotalViews,
        P.CreationDate
    FROM 
        Posts P
    WHERE 
        P.CreationDate >= NOW() - INTERVAL 1 YEAR
    GROUP BY 
        P.OwnerUserId, P.CreationDate
),
ClosedPostReasons AS (
    SELECT 
        PH.UserId,
        COUNT(*) AS CloseCount,
        GROUP_CONCAT(DISTINCT CRT.Name SEPARATOR ', ') AS CloseReasons
    FROM 
        PostHistory PH
    JOIN 
        CloseReasonTypes CRT ON CAST(PH.Comment AS UNSIGNED) = CRT.Id
    WHERE 
        PH.PostHistoryTypeId IN (10, 11) 
    GROUP BY 
        PH.UserId
),
UserPerformance AS (
    SELECT 
        UB.UserId,
        UB.DisplayName,
        COALESCE(PA.QuestionsCount, 0) AS Questions,
        COALESCE(PA.AnswersCount, 0) AS Answers,
        COALESCE(PA.TotalScore, 0) AS TotalScore,
        COALESCE(PA.TotalViews, 0) AS TotalViews,
        COALESCE(CPR.CloseCount, 0) AS ClosedPosts,
        COALESCE(CPR.CloseReasons, 'None') AS CloseReasons,
        UB.GoldBadges, 
        UB.SilverBadges, 
        UB.BronzeBadges
    FROM 
        UserBadges UB
    LEFT JOIN 
        PostAnalytics PA ON UB.UserId = PA.OwnerUserId
    LEFT JOIN 
        ClosedPostReasons CPR ON UB.UserId = CPR.UserId
)
SELECT 
    UPerformance.*,
    (SELECT COUNT(*) 
     FROM UserPerformance UP 
     WHERE UP.TotalScore > UPerformance.TotalScore) + 1 AS ScoreRank
FROM 
    UserPerformance UPerformance
WHERE 
    UPerformance.Questions > 5
ORDER BY 
    UPerformance.TotalViews DESC, UPerformance.TotalScore DESC;
