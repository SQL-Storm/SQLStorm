WITH TopActiveUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.Location, u.LastAccessDate,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM Users u
    WHERE u.LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
),
BadgeCounts AS (
    SELECT b.UserId, COUNT(*) AS TotalBadges, 
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
RecentPosts AS (
    SELECT p.OwnerUserId, COUNT(*) AS PostCount,
           SUM(p.ViewCount) AS TotalViews,
           SUM(p.CommentCount) AS TotalComments
    FROM Posts p
    WHERE p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' MONTH)
    GROUP BY p.OwnerUserId
),
AllPostsCount AS (
    SELECT OwnerUserId, COUNT(*) AS PostCount
    FROM Posts
    GROUP BY OwnerUserId
)
SELECT u.UserId, u.DisplayName, u.Reputation, b.TotalBadges, b.GoldBadges, 
       b.SilverBadges, b.BronzeBadges, COALESCE(rp.PostCount, 0) AS PostCount,
       COALESCE(rp.TotalViews, 0) AS TotalViews, COALESCE(rp.TotalComments, 0) AS TotalComments,
       CASE 
           WHEN ap.PostCount IS NULL THEN 'New User'
           WHEN ap.PostCount > 50 THEN 'Prolific Poster'
           ELSE 'Active User'
       END AS UserActivity,
       u.Rank
FROM TopActiveUsers u
LEFT JOIN BadgeCounts b ON u.UserId = b.UserId
LEFT JOIN RecentPosts rp ON u.UserId = rp.OwnerUserId
LEFT JOIN AllPostsCount ap ON u.UserId = ap.OwnerUserId
WHERE EXTRACT(DAY FROM u.LastAccessDate) = EXTRACT(DAY FROM TIMESTAMP '2024-10-01 12:34:56')
GROUP BY u.UserId, u.DisplayName, u.Reputation, b.TotalBadges, b.GoldBadges, b.SilverBadges, b.BronzeBadges, rp.PostCount, rp.TotalViews, rp.TotalComments, ap.PostCount, u.Rank, u.LastAccessDate
ORDER BY u.Rank;