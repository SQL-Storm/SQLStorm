WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentsCount
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
AvgVotes AS (
    SELECT 
        OwnerUserId,
        AVG(UpVotesCount) AS AvgUpVotes
    FROM 
        RankedPosts
    WHERE 
        rn <= 10
    GROUP BY 
        OwnerUserId
),
UserDetails AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COALESCE(b.Name, 'No Badge') AS BadgeName,
        ad.AvgUpVotes
    FROM 
        Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN AvgVotes ad ON u.Id = ad.OwnerUserId
)
SELECT 
    ud.DisplayName,
    ud.Reputation,
    ud.Location,
    ud.BadgeName,
    COUNT(DISTINCT rp.PostId) AS PostsCount,
    SUM(rp.UpVotesCount) AS TotalUpVotes,
    MIN(rp.CreationDate) AS FirstPostDate,
    MAX(rp.CreationDate) AS LastPostDate,
    ud.AvgUpVotes
FROM 
    UserDetails ud
LEFT JOIN RankedPosts rp ON ud.Id = rp.OwnerUserId
GROUP BY 
    ud.DisplayName,
    ud.Reputation,
    ud.Location,
    ud.BadgeName,
    ud.Id,
    ud.AvgUpVotes
HAVING 
    COUNT(DISTINCT rp.PostId) > 5
ORDER BY 
    TotalUpVotes DESC
LIMIT 10;