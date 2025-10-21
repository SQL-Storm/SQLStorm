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
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId IN (1, 2) AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        p.Id, u.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, u.Reputation, u.DisplayName
),
TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        u.CreationDate, 
        COUNT(b.Id) AS BadgeCount, 
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS UserRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostTagCounts AS (
    SELECT 
        p.Id, 
        COUNT(DISTINCT t.TagName) AS TagCount
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId IN (1, 2) AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY 
        p.Id
)
SELECT 
    rp.Id, 
    rp.PostTypeId, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.UserReputation, 
    rp.UserDisplayName, 
    rp.VoteCount, 
    rp.CommentCount, 
    rp.PostRank, 
    tu.DisplayName AS TopUserDisplayName, 
    tu.Reputation AS TopUserReputation, 
    tu.UserRank, 
    ptc.TagCount
FROM 
    RankedPosts rp
JOIN 
    TopUsers tu ON rp.UserReputation >= tu.Reputation
JOIN 
    PostTagCounts ptc ON rp.Id = ptc.Id
WHERE 
    rp.PostRank <= 100 AND tu.UserRank <= 100
ORDER BY 
    rp.Score DESC, 
    rp.CreationDate, 
    tu.Reputation DESC;