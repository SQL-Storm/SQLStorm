
WITH UserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT SUBSTRING_INDEX(SUBSTRING_INDEX(p.Tags, '><', n.n), '><', -1) AS TagName
          FROM Posts p
          JOIN (SELECT a.N + b.N * 10 AS n
                FROM (SELECT 0 AS N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 
                      UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a
                CROSS JOIN (SELECT 0 AS N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 
                            UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b
               ) n
          WHERE n.n <= 1 + (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', ''))) 
    ) t ON TRUE
    GROUP BY u.Id, u.DisplayName, t.TagName
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostsActivity AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        h.UserDisplayName,
        h.Comment,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY h.CreationDate DESC) AS ActivityRank
    FROM Posts p
    LEFT JOIN PostHistory h ON p.Id = h.PostId
    WHERE p.CreationDate >= DATE_SUB('2024-10-01', INTERVAL 30 DAY)
),
TopUsers AS (
    SELECT 
        ut.UserId,
        ut.DisplayName,
        SUM(ut.PostCount) AS TotalPosts,
        SUM(ub.GoldBadges) AS TotalGoldBadges,
        SUM(ub.SilverBadges) AS TotalSilverBadges,
        SUM(ub.BronzeBadges) AS TotalBronzeBadges
    FROM UserTags ut
    LEFT JOIN UserBadges ub ON ut.UserId = ub.UserId
    GROUP BY ut.UserId, ut.DisplayName
    ORDER BY TotalPosts DESC
    LIMIT 10
),
PostMetrics AS (
    SELECT 
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate >= DATE_SUB('2024-10-01', INTERVAL 6 MONTH)
    GROUP BY p.Id, p.Title, p.ViewCount, p.Score
)
SELECT 
    tu.DisplayName,
    tu.TotalPosts,
    tu.TotalGoldBadges,
    tu.TotalSilverBadges,
    tu.TotalBronzeBadges,
    pm.Title,
    pm.ViewCount,
    pm.Score,
    pm.CommentCount,
    pm.UpVotes,
    pm.DownVotes
FROM TopUsers tu
JOIN PostMetrics pm ON pm.Id IN (
    SELECT p.Id 
    FROM Posts p 
    ORDER BY p.ViewCount DESC 
    LIMIT 5
)
ORDER BY tu.TotalPosts DESC;
