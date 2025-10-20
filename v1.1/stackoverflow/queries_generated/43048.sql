-- {"query": "43048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 822} 

WITH RecentActivePosts AS (
    SELECT 
        p.Id, 
        p.OwnerUserId, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.FavoriteCount, 
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
),
UserBadges AS (
    SELECT 
        b.UserId, 
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopContributors AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS AcceptedAnswers,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT ph.PostId) AS EditCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN UserBadges ub ON u.Id = ub.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
),
TagPerformance AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT CASE WHEN p.Score >= 10 THEN p.Id END) AS HighScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) AS NegativeScorePosts,
        AVG(p.ViewCount) AS AvgViewCount
    FROM Tags t
    JOIN Posts p ON POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY t.TagName
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.Reputation,
    tc.AcceptedAnswers,
    tc.QuestionCount,
    tc.EditCount,
    tc.GoldBadges,
    tc.SilverBadges,
    tc.BronzeBadges,
    tp.TagName,
    tp.HighScorePosts,
    tp.NegativeScorePosts,
    tp.AvgViewCount
FROM TopContributors tc
JOIN RecentActivePosts rap ON tc.UserId = rap.OwnerUserId
JOIN Tags t ON POSITION(CONCAT('<', t.TagName, '>') IN rap.Tags) > 0
JOIN TagPerformance tp ON t.TagName = tp.TagName
WHERE rap.rn <= 5
ORDER BY tc.Reputation DESC, tp.HighScorePosts DESC
LIMIT 100;
