WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.Reputation,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalViews,
        SUM(COALESCE(V.BountyAmount, 0)) AS TotalBounty
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId AND V.VoteTypeId = 8
    GROUP BY 
        U.Id, U.Reputation, U.DisplayName
),
ClosingHistory AS (
    SELECT 
        PH.UserId,
        COUNT(*) AS CloseCount,
        MIN(PH.CreationDate) AS FirstCloseDate
    FROM 
        PostHistory PH
    WHERE 
        PH.PostHistoryTypeId = 10
    GROUP BY 
        PH.UserId
),
TopUsers AS (
    SELECT 
        UR.UserId,
        UR.Reputation,
        UR.PostCount,
        UR.TotalViews,
        UR.TotalBounty,
        COALESCE(CH.CloseCount, 0) AS CloseCount,
        CH.FirstCloseDate,
        UR.DisplayName
    FROM 
        UserReputation UR
    LEFT JOIN 
        ClosingHistory CH ON UR.UserId = CH.UserId
    WHERE 
        UR.Reputation > 1000 AND UR.PostCount > 5
    ORDER BY 
        UR.Reputation DESC
    LIMIT 10
)
SELECT 
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.PostCount,
    TU.TotalViews,
    TU.CloseCount,
    TU.FirstCloseDate,
    CASE 
        WHEN TU.CloseCount > 0 THEN 'Yes'
        ELSE 'No'
    END AS HasClosedPosts
FROM 
    TopUsers TU
ORDER BY 
    TU.Reputation DESC, TU.TotalViews DESC;