WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalScore,
        MAX(U.LastAccessDate) AS LastActive
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.OwnerUserId IS NOT NULL
    GROUP BY 
        U.Id, U.DisplayName
),
TopQuestions AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        COALESCE(NULLIF(U.DisplayName, ''), 'Anonymous') AS OwnerDisplayName,
        P.OwnerUserId AS OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 
        AND P.Score > (SELECT AVG(CAST(Score AS NUMERIC)) FROM Posts WHERE PostTypeId = 1)
),
UserBadges AS (
    SELECT 
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
)
SELECT 
    UA.UserId,
    UA.DisplayName,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalScore,
    UA.LastActive,
    COALESCE(UB.GoldBadges, 0) AS GoldBadges,
    COALESCE(UB.SilverBadges, 0) AS SilverBadges,
    COALESCE(UB.BronzeBadges, 0) AS BronzeBadges,
    TQ.Title AS TopQuestionTitle,
    TQ.Score AS TopQuestionScore,
    TQ.ViewCount AS TopQuestionViewCount,
    STRING_AGG(DISTINCT COALESCE(T.TagName, ''), ', ') AS TagsUsed
FROM 
    UserActivity UA
LEFT JOIN 
    TopQuestions TQ ON UA.UserId = TQ.OwnerUserId AND TQ.Rank = 1
LEFT JOIN 
    UserBadges UB ON UA.UserId = UB.UserId
LEFT JOIN 
    Posts P ON UA.UserId = P.OwnerUserId
LEFT JOIN 
    Tags T ON P.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
WHERE 
    UA.TotalScore > (SELECT AVG(TotalScore) FROM UserActivity WHERE TotalPosts > 0)
GROUP BY 
    UA.UserId, UA.DisplayName, UA.TotalPosts, UA.TotalQuestions, UA.TotalAnswers, UA.TotalScore, UA.LastActive,
    UB.GoldBadges, UB.SilverBadges, UB.BronzeBadges,
    TQ.Title, TQ.Score, TQ.ViewCount, TQ.OwnerUserId
ORDER BY 
    UA.TotalScore DESC, UA.TotalPosts DESC, TQ.Score DESC
LIMIT 100;