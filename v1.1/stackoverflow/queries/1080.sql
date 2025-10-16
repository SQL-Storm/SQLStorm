WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
        AND p.Score > 0
), 
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COALESCE(SUM(b.Class), 0) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id,
        u.Reputation
),
RecentVotes AS (
    SELECT 
        v.PostId,
        COUNT(v.Id) AS VoteCount,
        MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasUpVote
    FROM 
        Votes v
    WHERE 
        v.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY 
        v.PostId
)

SELECT 
    rp.Id AS PostId,
    rp.Title,
    ur.Reputation,
    ur.PostCount,
    ur.BadgeCount,
    COALESCE(rv.VoteCount, 0) AS VoteCount,
    COALESCE(rv.HasUpVote, 0) AS HasUpVote,
    rp.CreationDate,
    CASE 
        WHEN COALESCE(rv.HasUpVote, 0) = 1 THEN 'Upvoted' 
        ELSE 'Not Upvoted' 
    END AS VoteStatus,
    CASE 
        WHEN rp.UserPostRank <= 5 THEN 'Top Recent Post' 
        ELSE 'Other Post' 
    END AS PostCategory
FROM 
    RankedPosts rp
JOIN 
    UserReputation ur ON rp.OwnerUserId = ur.UserId
LEFT JOIN 
    RecentVotes rv ON rp.Id = rv.PostId
WHERE 
    ur.Reputation > 1000
GROUP BY
    rp.Id,
    rp.Title,
    ur.Reputation,
    ur.PostCount,
    ur.BadgeCount,
    rv.VoteCount,
    rv.HasUpVote,
    rp.CreationDate,
    rp.UserPostRank
ORDER BY 
    rp.CreationDate DESC
FETCH FIRST 10 ROWS ONLY;