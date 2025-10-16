-- {"query": "10021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 593} 

WITH Ranked_Badges AS (
    SELECT 
        B.UserId,
        B.Name,
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Date DESC) AS rn
    FROM 
        Badges B
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
),
Filtered_Posts AS (
    SELECT 
        P.Id,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        U.DisplayName,
        U.Reputation,
        U.Location,
        U.AboutMe,
        U.WebsiteUrl,
        U.AccountId,
        CASE 
            WHEN P.PostTypeId = 1 THEN 'Question'
            WHEN P.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.ViewCount > 1000 AND P.Score > 0 AND P.LastActivityDate > P.CreationDate
),
Post_Votes_Summary AS (
    SELECT 
        FP.Id,
        SUM(V.BountyAmount) AS TotalBounty,
        COUNT(DISTINCT V.UserId) AS TotalVoters
    FROM 
        Filtered_Posts FP
    JOIN 
        Votes V ON FP.Id = V.PostId AND V.VoteTypeId = 8
    GROUP BY 
        FP.Id
)
SELECT 
    FP.Id,
    FP.OwnerUserId,
    FP.Score,
    FP.ViewCount,
    FP.CreationDate,
    FP.LastActivityDate,
    FP.Title,
    FP.Tags,
    FP.DisplayName,
    FP.Reputation,
    FP.Location,
    FP.AboutMe,
    FP.WebsiteUrl,
    FP.AccountId,
    FP.PostType,
    PVS.TotalBounty,
    PVS.TotalVoters,
    RB.Name AS TopBadge,
    RB.rn
FROM 
    Filtered_Posts FP
LEFT JOIN 
    Post_Votes_Summary PVS ON FP.Id = PVS.Id
LEFT JOIN (
    SELECT 
        UserId,
        Name,
        rn
    FROM 
        Ranked_Badges
    WHERE 
        rn = 1
) RB ON FP.OwnerUserId = RB.UserId
WHERE 
    FP.ViewCount > 10000 OR (FP.Score > 100 AND FP.TotalVoters > 5)
ORDER BY 
    FP.Score DESC, 
    FP.ViewCount DESC;
