-- {"query": "32031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 455} 
WITH TopUsersByReputation AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000 
    ORDER BY Reputation DESC
    LIMIT 100
),
UserPosts AS (
    SELECT p.OwnerUserId, COUNT(*) AS PostCount, SUM(p.Score) AS TotalScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY p.OwnerUserId
),
UserComments AS (
    SELECT c.UserId, COUNT(*) AS CommentCount, AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount, SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    u.DisplayName,
    u.Reputation,
    COALESCE(up.PostCount, 0) AS PostCount,
    COALESCE(up.TotalScore, 0) AS TotalScore,
    COALESCE(uc.CommentCount, 0) AS CommentCount,
    COALESCE(uc.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(ub.BadgeCount, 0) AS BadgeCount,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges
FROM TopUsersByReputation u
LEFT JOIN UserPosts up ON u.Id = up.OwnerUserId
LEFT JOIN UserComments uc ON u.Id = uc.UserId
LEFT JOIN UserBadges ub ON u.Id = ub.UserId
ORDER BY u.Reputation DESC, PostCount DESC, BadgeCount DESC;