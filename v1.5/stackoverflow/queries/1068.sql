WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.OwnerUserId
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        SUM(v.BountyAmount) AS TotalBounties,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN 
        Votes v ON u.Id = v.UserId AND v.VoteTypeId = 9
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    ua.TotalBounties,
    ua.QuestionCount,
    ua.GoldBadges,
    rp.Title,
    rp.ViewCount,
    rp.CreationDate
FROM 
    UserActivity ua
JOIN 
    RankedPosts rp ON ua.UserId = rp.PostId
WHERE 
    ua.Reputation > 500 AND 
    rp.PostRank = 1
ORDER BY 
    ua.Reputation DESC NULLS LAST, 
    rp.ViewCount DESC
LIMIT 100;