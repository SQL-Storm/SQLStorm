
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year' AND 
        p.Score > 0
),
RecentBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount,
        LISTAGG(b.Name, ', ') WITHIN GROUP (ORDER BY b.Name) AS BadgeNames
    FROM 
        Badges b
    WHERE 
        b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
    GROUP BY 
        b.UserId
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(rb.BadgeCount, 0) AS RecentBadgeCount,
        COALESCE(rb.BadgeNames, 'None') AS RecentBadges,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentTotal,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AS VoteTotal
    FROM 
        Users u
    LEFT JOIN 
        RecentBadges rb ON u.Id = rb.UserId
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.RecentBadgeCount,
    u.RecentBadges,
    p.PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount
FROM 
    UserActivity u
JOIN 
    RankedPosts p ON u.UserId = p.PostId
WHERE 
    p.PostRank <= 5 
ORDER BY 
    u.Reputation DESC, p.CreationDate DESC
LIMIT 100;
