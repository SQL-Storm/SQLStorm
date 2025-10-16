-- {"query": "2089.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 496} 
WITH UserBadgeCount AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
RecentPosts AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS RecentPostsCount
    FROM Posts p
    WHERE p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY p.OwnerUserId
),
VoteSummary AS (
    SELECT
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
TopUsersWithVotes AS (
    SELECT
        v.OwnerUserId,
        u.DisplayName,
        v.UpVotes,
        v.DownVotes,
        r.RecentPostsCount,
        ROW_NUMBER() OVER(PARTITION BY v.OwnerUserId ORDER BY (v.UpVotes - v.DownVotes) DESC) AS Rank
    FROM VoteSummary v
    JOIN Users u ON v.OwnerUserId = u.Id
    LEFT JOIN RecentPosts r ON v.OwnerUserId = r.OwnerUserId
)
SELECT 
    t.DisplayName,
    t.UpVotes,
    t.DownVotes,
    COALESCE(t.RecentPostsCount, 0) AS RecentPostsCount,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges
FROM UserBadgeCount ub
JOIN TopUsersWithVotes t ON ub.UserId = t.OwnerUserId
WHERE t.Rank = 1
ORDER BY (t.UpVotes - t.DownVotes) DESC, ub.TotalBadges DESC
LIMIT 10;