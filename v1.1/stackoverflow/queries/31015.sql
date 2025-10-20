WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        p.OwnerUserId
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId
), TopRankedPosts AS (
    SELECT 
        PostId, 
        Title, 
        Score, 
        ViewCount, 
        CreationDate, 
        VoteCount,
        OwnerUserId
    FROM 
        RankedPosts
    WHERE 
        RecentPostRank <= 5
), UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(bp.Id) AS PostCount
    FROM 
        Users u
    LEFT JOIN 
        Posts bp ON u.Id = bp.OwnerUserId AND bp.PostTypeId = 1
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
)
SELECT 
    ur.DisplayName,
    ur.Reputation,
    ur.PostCount,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.CreationDate,
    tp.VoteCount
FROM 
    UserReputation ur
JOIN 
    TopRankedPosts tp ON ur.UserId = tp.OwnerUserId
ORDER BY 
    ur.Reputation DESC, tp.Score DESC;