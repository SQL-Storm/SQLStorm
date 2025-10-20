-- {"query": "43025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 517} 

WITH ActiveUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT B.Id) AS TotalBadges
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.LastAccessDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
    HAVING 
        COUNT(DISTINCT P.Id) > 10
),
TopQuestions AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.Tags,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS Rank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1 
        AND P.Score > 10
),
RecentActivity AS (
    SELECT 
        PH.UserId,
        COUNT(PH.Id) AS EditCount
    FROM 
        PostHistory PH
    WHERE 
        PH.CreationDate > CURRENT_DATE - INTERVAL '1 month' 
        AND PH.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY 
        PH.UserId
)
SELECT 
    AU.Id,
    AU.DisplayName,
    AU.Reputation,
    AU.TotalPosts,
    AU.TotalBadges,
    TQ.Title AS TopQuestionTitle,
    TQ.Score AS TopQuestionScore,
    RA.EditCount
FROM 
    ActiveUsers AU
LEFT JOIN 
    TopQuestions TQ ON AU.Id = TQ.OwnerUserId AND TQ.Rank = 1
LEFT JOIN 
    RecentActivity RA ON AU.Id = RA.UserId
ORDER BY 
    AU.Reputation DESC, 
    TQ.Score DESC, 
    RA.EditCount DESC
LIMIT 100;
