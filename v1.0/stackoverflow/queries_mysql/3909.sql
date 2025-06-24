
WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM 
        Users U
), 

PostsStats AS (
    SELECT 
        P.OwnerUserId,
        COUNT(*) AS TotalPosts,
        SUM(IFNULL(P.Score, 0)) AS TotalScore,
        SUM(IFNULL(P.ViewCount, 0)) AS TotalViews,
        SUM(IF(P.PostTypeId = 1, 1, 0)) AS QuestionCount,
        SUM(IF(P.PostTypeId = 2, 1, 0)) AS AnswerCount
    FROM 
        Posts P
    GROUP BY 
        P.OwnerUserId
), 

ClosedPosts AS (
    SELECT 
        PH.UserId, 
        COUNT(*) AS ClosedPostCount
    FROM 
        PostHistory PH
    WHERE 
        PH.PostHistoryTypeId = 10  
    GROUP BY 
        PH.UserId
)

SELECT 
    U.DisplayName,
    U.Reputation,
    UR.ReputationRank,
    PS.TotalPosts,
    PS.TotalScore,
    PS.TotalViews,
    PS.QuestionCount,
    PS.AnswerCount,
    COALESCE(CP.ClosedPostCount, 0) AS ClosedPostCount,
    CASE 
        WHEN UR.ReputationRank <= 10 THEN 'Top Contributor'
        WHEN UR.ReputationRank <= 50 THEN 'Valuable Contributor'
        ELSE 'Regular Contributor' 
    END AS ContributorType
FROM 
    Users U
LEFT JOIN 
    UserReputation UR ON U.Id = UR.UserId
LEFT JOIN 
    PostsStats PS ON U.Id = PS.OwnerUserId
LEFT JOIN 
    ClosedPosts CP ON U.Id = CP.UserId
WHERE 
    U.Reputation > 0
ORDER BY 
    U.Reputation DESC, 
    PS.TotalScore DESC
LIMIT 100;
