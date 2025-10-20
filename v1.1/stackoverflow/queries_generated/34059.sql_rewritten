-- {"query": "34059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 754} 
WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           SUM(COALESCE(p.Score,0)) AS TotalPostScore,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           MAX(b.Class) AS HighestBadgeClass
      FROM Users u
      LEFT JOIN Posts p ON p.OwnerUserId = u.Id
      LEFT JOIN Badges b ON b.UserId = u.Id
     WHERE u.Reputation > 1000
     GROUP BY u.Id, u.DisplayName, u.Reputation
     HAVING COUNT(DISTINCT p.Id) > 10
),
RecentHighImpactPosts AS (
    SELECT p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate, p.Title,
           ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
      FROM Posts p
     WHERE p.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year'
       AND p.PostTypeId IN (1,2) -- Questions and Answers
),
UserRecentTopPosts AS (
    SELECT rhp.* FROM RecentHighImpactPosts rhp
    JOIN TopUsers tu ON tu.Id = rhp.OwnerUserId
    WHERE rhp.rn <= 3
),
PostCommentsCount AS (
    SELECT c.PostId, COUNT(*) AS CommentsCount
      FROM Comments c
     GROUP BY c.PostId
),
UserBadgeSummary AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
      FROM Badges b
     GROUP BY b.UserId
),
UserAnswerStats AS (
    SELECT p.OwnerUserId,
           COUNT(*) AS AnswerCount,
           AVG(p.Score) AS AverageAnswerScore,
           MAX(p.Score) AS MaxAnswerScore
      FROM Posts p
     WHERE p.PostTypeId = 2
     GROUP BY p.OwnerUserId
)
SELECT 
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    COALESCE(ub.GoldBadges,0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    ua.AnswerCount,
    ROUND(ua.AverageAnswerScore,2) AS AverageAnswerScore,
    ua.MaxAnswerScore,
    urtp.Id AS PostId,
    CASE urtp.PostTypeId WHEN 1 THEN 'Question' WHEN 2 THEN 'Answer' ELSE 'Other' END AS PostType,
    urtp.Score AS PostScore,
    urtp.ViewCount,
    urtp.Title,
    COALESCE(pc.CommentsCount,0) AS CommentsCount,
    tu.TotalPosts,
    tu.TotalPostScore
FROM TopUsers tu
LEFT JOIN UserBadgeSummary ub ON ub.UserId = tu.Id
LEFT JOIN UserAnswerStats ua ON ua.OwnerUserId = tu.Id
LEFT JOIN UserRecentTopPosts urtp ON urtp.OwnerUserId = tu.Id
LEFT JOIN PostCommentsCount pc ON pc.PostId = urtp.Id
ORDER BY tu.Reputation DESC, ua.MaxAnswerScore DESC, urtp.Score DESC
LIMIT 100;