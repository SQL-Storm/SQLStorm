WITH PostStats AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        COALESCE(NULLIF(SUM(V.BountyAmount), 0), 0) AS TotalBounty,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT A.Id) FILTER (WHERE A.PostTypeId = 2) AS AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserPostRank
    FROM 
        Posts P
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Posts A ON P.Id = A.ParentId
    WHERE 
        P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        P.Id
), RankedPosts AS (
    SELECT 
        PS.*,
        RANK() OVER (ORDER BY PS.TotalBounty DESC) AS BountyRank
    FROM 
        PostStats PS
)

SELECT 
    RP.PostId,
    RP.Title,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.TotalBounty,
    RP.CommentCount,
    RP.AnswerCount,
    RP.UserPostRank,
    CASE 
        WHEN RP.BountyRank <= 10 THEN 'Top Bounty'
        ELSE 'Regular Post'
    END AS PostCategory
FROM 
    RankedPosts RP
WHERE 
    RP.UserPostRank <= 5
ORDER BY 
    RP.BountyRank, RP.Score DESC;

-- Additionally, to demonstrate NULL logic, the query can filter out specific conditions.
SELECT 
    COALESCE(NULLIF(RP.TotalBounty, 0), 'No Bounty') AS Bounty_Info,
    RP.*
FROM 
    RankedPosts RP
WHERE 
    RP.CommentCount > 5 OR RP.AnswerCount > 2;
