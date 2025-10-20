WITH UserActivity AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(DISTINCT p.Id) AS TotalPosts,
           COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= DATE '2022-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
PostPerformance AS (
    SELECT p.Id AS PostId,
           p.OwnerUserId,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
),
AggregatedData AS (
    SELECT ua.UserId,
           ua.DisplayName,
           ua.Reputation,
           AVG(pp.Score) AS AvgScore,
           AVG(pp.ViewCount) AS AvgViewCount,
           SUM(pp.CommentCount) AS TotalComments
    FROM UserActivity ua
    JOIN PostPerformance pp ON ua.UserId = pp.OwnerUserId
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation
    ORDER BY AVG(pp.Score) DESC, AVG(pp.ViewCount) DESC
    LIMIT 100
)
SELECT ad.UserId,
       ad.DisplayName,
       ad.Reputation,
       ad.AvgScore,
       ad.AvgViewCount,
       ad.TotalComments,
       (SELECT COUNT(*) FROM Badges WHERE UserId = ad.UserId AND Class = 1) AS GoldBadges,
       (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ad.UserId AND PostTypeId = 2 AND Score > 10) AS QualityAnswers
FROM AggregatedData ad
WHERE ad.TotalComments > 50;