WITH RecentUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        COALESCE(p.Score * 1.0 / NULLIF(p.ViewCount, 0), 0) AS ScorePerView,
        COUNT(a.Id) AS AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
    HAVING COUNT(a.Id) = (
        SELECT MAX(sub.AnswerCount) FROM (
            SELECT p2.Id, COUNT(a2.Id) AS AnswerCount
            FROM Posts p2
            LEFT JOIN Posts a2 ON p2.Id = a2.ParentId AND a2.PostTypeId = 2
            WHERE p2.PostTypeId = 1
            GROUP BY p2.Id
        ) AS sub
    )
),
BadgeStatistics AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    tq.Title AS TopQuestionTitle,
    COALESCE(tq.ScorePerView, 0) AS ScorePerView,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    CASE 
        WHEN u.Reputation >= 10000 THEN 'Top Contributor'
        WHEN u.Reputation >= 5000 THEN 'Active Contributor'
        ELSE 'Newbie'
    END AS ContributionLevel
FROM RecentUsers u
LEFT JOIN TopQuestions tq ON u.Id = tq.OwnerUserId AND tq.rn = 1
LEFT JOIN BadgeStatistics bs ON u.Id = bs.UserId
WHERE COALESCE(bs.GoldBadges, 0) + COALESCE(bs.SilverBadges, 0) + COALESCE(bs.BronzeBadges, 0) > 0
ORDER BY u.Reputation DESC, COALESCE(bs.GoldBadges, 0) DESC, COALESCE(bs.SilverBadges, 0) DESC, COALESCE(bs.BronzeBadges, 0) DESC;