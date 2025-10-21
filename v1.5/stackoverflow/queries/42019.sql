WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.Reputation AS UserReputation, 
        u.DisplayName AS UserDisplayName, 
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId IN (1, 2) AND 
        p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        p.Id, u.Reputation, u.DisplayName, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount
), 
TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(p.Id) AS PostCount, 
        SUM(p.Score) AS TotalScore, 
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(p.Id) DESC) AS UserRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
)
SELECT 
    rp.Id AS PostId, 
    rp.PostTypeId, 
    rp.CreationDate AS PostCreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.UserReputation, 
    rp.UserDisplayName, 
    rp.VoteCount, 
    rp.CommentCount, 
    rp.PostRank, 
    tu.Id AS UserId, 
    tu.DisplayName AS TopUserDisplayName, 
    tu.Reputation AS TopUserReputation, 
    tu.PostCount, 
    tu.TotalScore, 
    tu.UserRank
FROM 
    RankedPosts rp
JOIN 
    TopUsers tu ON rp.UserDisplayName = tu.DisplayName
WHERE 
    rp.PostRank <= 10 AND 
    tu.UserRank <= 10
ORDER BY 
    rp.PostRank, 
    tu.UserRank;