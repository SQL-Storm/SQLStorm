
WITH UserBadgeCounts AS (
    SELECT 
        b.UserId, 
        COUNT(b.Id) AS BadgeCount,
        MAX(b.Class) AS HighestBadgeClass
    FROM Badges b
    GROUP BY b.UserId
),
RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate >= (NOW() - INTERVAL 7 DAY) 
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.CreationDate
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        ub.BadgeCount,
        up.PostId,
        up.Title,
        up.CreationDate,
        up.CommentCount,
        up.UpVoteCount,
        (SELECT COUNT(*) FROM RecentPosts up_sub WHERE up_sub.UpVoteCount > up.UpVoteCount AND ub.BadgeCount = ub.BadgeCount) + 1 AS UserRank
    FROM Users u
    JOIN UserBadgeCounts ub ON u.Id = ub.UserId
    JOIN RecentPosts up ON u.Id = up.OwnerUserId
)
SELECT 
    t.DisplayName,
    t.Title,
    t.CreationDate,
    t.CommentCount,
    t.UpVoteCount,
    CASE 
        WHEN t.UserRank <= 3 THEN 'Top Contributor'
        ELSE 'Contributor'
    END AS ContributionLevel
FROM 
    TopUsers t
WHERE 
    t.BadgeCount > 0
ORDER BY 
    t.BadgeCount DESC, 
    t.UpVoteCount DESC
LIMIT 10;
