-- {"query": "23068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 951} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS PostCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(AVG(p.ViewCount), 0) AS AvgViewCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(*) > 0
),
TopPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        (SELECT AVG(c.Score) FROM Comments c WHERE c.PostId = p.Id) AS AvgCommentScore,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS PostRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount IS NOT NULL
),
TagUsage AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        STRING_AGG(COALESCE(p.Tags, ''), ', ') AS AssociatedTags
    FROM Tags t
    LEFT OUTER JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
    GROUP BY t.Id, t.TagName, t.Count
),
CombinedStats AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.UserCreationDate,
        us.PostCount,
        us.TotalScore,
        us.AvgViewCount,
        us.ReputationRank,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        bs.LatestBadgeDate,
        tp.PostId AS TopPostId,
        tp.Title AS TopPostTitle,
        tp.ViewCount AS TopPostViewCount,
        tp.AvgCommentScore,
        (us.Reputation / NULLIF(DATEDIFF(day, us.UserCreationDate, GETDATE()), 0)) AS RepPerDay,
        CASE 
            WHEN us.PostCount > 0 THEN 'Active Poster' 
            ELSE 'Observer' 
        END AS UserType
    FROM UserStats us
    LEFT OUTER JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT OUTER JOIN TopPosts tp ON us.UserId = tp.OwnerUserId AND tp.PostRank = 1
    WHERE us.ReputationRank <= 100
    UNION
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        0 AS PostCount,
        0 AS TotalScore,
        0 AS AvgViewCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation ASC) + (SELECT COUNT(*) FROM UserStats) AS ReputationRank,
        0 AS GoldBadges,
        0 AS SilverBadges,
        NULL AS LatestBadgeDate,
        NULL AS TopPostId,
        NULL AS TopPostTitle,
        NULL AS TopPostViewCount,
        NULL AS AvgCommentScore,
        0 AS RepPerDay,
        'Inactive' AS UserType
    FROM Users u
    WHERE u.Id NOT IN (SELECT UserId FROM UserStats) AND u.Reputation <= 1
)
SELECT 
    cs.*,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = cs.UserId) AND v.VoteTypeId = 2) AS UpvotesReceived,
    COALESCE((SELECT TOP 1 tu.TagName FROM TagUsage tu WHERE tu.TagCount > 1000 ORDER BY tu.TagCount DESC), 'No Popular Tags') AS MostPopularTag
FROM CombinedStats cs
WHERE cs.RepPerDay > 0 OR cs.GoldBadges > 0
ORDER BY cs.ReputationRank;
