WITH TopUsersByReputation AS (
    SELECT Id AS UserId, DisplayName, Reputation
    FROM Users
    ORDER BY Reputation DESC
    LIMIT 100
),
UserPostSummary AS (
    SELECT u.UserId, COUNT(p.Id) AS TotalPosts, SUM(p.Score) AS TotalScore, AVG(p.ViewCount) AS AvgViews
    FROM TopUsersByReputation u
    JOIN Posts p ON u.UserId = p.OwnerUserId
    GROUP BY u.UserId
),
UserCommentSummary AS (
    SELECT u.UserId, COUNT(c.Id) AS TotalComments, SUM(c.Score) AS TotalCommentScore
    FROM TopUsersByReputation u
    JOIN Comments c ON u.UserId = c.UserId
    GROUP BY u.UserId
),
UserBadgeSummary AS (
    SELECT u.UserId, COUNT(b.Id) AS TotalBadges, 
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM TopUsersByReputation u
    JOIN Badges b ON u.UserId = b.UserId
    GROUP BY u.UserId
)
SELECT u.UserId, u.DisplayName, ups.TotalPosts, ups.TotalScore, ups.AvgViews, 
       ucs.TotalComments, ucs.TotalCommentScore, 
       ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, u.Reputation
FROM TopUsersByReputation u
LEFT JOIN UserPostSummary ups ON u.UserId = ups.UserId
LEFT JOIN UserCommentSummary ucs ON u.UserId = ucs.UserId
LEFT JOIN UserBadgeSummary ubs ON u.UserId = ubs.UserId
ORDER BY u.Reputation DESC;