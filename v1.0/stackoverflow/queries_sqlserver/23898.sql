
WITH RankedPosts AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS Rank,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerId
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.CreationDate >= CAST(DATEADD(MONTH, -2, '2024-10-01') AS DATE) 
        AND P.Score IS NOT NULL
),
ClosedPosts AS (
    SELECT 
        PH.PostId,
        PH.CreationDate AS ClosedDate,
        CR.Name AS CloseReason
    FROM 
        PostHistory PH
    JOIN 
        CloseReasonTypes CR ON CAST(PH.Comment AS INT) = CR.Id
    WHERE 
        PH.PostHistoryTypeId IN (10, 11) 
),
TopPosts AS (
    SELECT 
        RP.PostId,
        RP.Title,
        RP.CreationDate,
        RP.Score,
        RP.ViewCount,
        RP.OwnerDisplayName,
        CP.ClosedDate,
        CP.CloseReason,
        (SELECT AVG(V.BountyAmount) 
         FROM Votes V 
         WHERE V.PostId = RP.PostId 
               AND V.VoteTypeId IN (8, 9)) AS AverageBounty
    FROM 
        RankedPosts RP
    LEFT JOIN 
        ClosedPosts CP ON RP.PostId = CP.PostId
    WHERE 
        RP.Rank <= 5
)
SELECT 
    T.Title,
    T.CreationDate,
    T.Score,
    T.ViewCount,
    T.OwnerDisplayName,
    CASE 
        WHEN T.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Active'
    END AS PostStatus,
    COALESCE(T.CloseReason, 'N/A') AS CloseReason,
    CASE 
        WHEN T.AverageBounty IS NULL THEN 'No Bounty'
        ELSE 'Average Bounty: ' + CAST(T.AverageBounty AS NVARCHAR)
    END AS BountyInfo,
    '<a href="https://example.com/posts/' + CAST(T.PostId AS NVARCHAR) + '">View Post</a>' AS PostLink
FROM 
    TopPosts T
ORDER BY 
    T.Score DESC, 
    T.CreationDate DESC;
