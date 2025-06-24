WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserRank,
        COUNT(v.Id) AS VoteCount
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.OwnerUserId
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
PostDetails AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.CreationDate,
        tu.DisplayName AS OwnerName,
        tu.TotalScore AS OwnerTotalScore,
        tu.PostCount AS OwnerPostCount,
        rp.VoteCount
    FROM 
        RankedPosts rp
    JOIN 
        TopUsers tu ON rp.OwnerUserId = tu.UserId
    WHERE 
        rp.UserRank <= 5
)
SELECT 
    pd.PostId,
    pd.Title,
    pd.Score,
    pd.CreationDate,
    pd.OwnerName,
    pd.OwnerTotalScore,
    pd.OwnerPostCount,
    pd.VoteCount
FROM 
    PostDetails pd
ORDER BY 
    pd.Score DESC, 
    pd.CreationDate DESC;
