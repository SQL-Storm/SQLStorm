WITH UsersWithBadges AS (
    SELECT u.Id AS UserId, 
           u.DisplayName, 
           COUNT(b.Id) AS BadgeCount, 
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
RankedPosts AS (
    SELECT p.Id, 
           p.Title, 
           p.CreationDate, 
           p.Score, 
           p.OwnerUserId,
           COUNT(c.Id) AS CommentCount,
           DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') 
      AND p.Score > 0
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.OwnerUserId
)
SELECT u.DisplayName, 
       u.Reputation, 
       u.AboutMe, 
       up.BadgeCount, 
       up.GoldCount, 
       up.SilverCount, 
       up.BronzeCount,
       rp.Title AS TopPostTitle, 
       rp.CreationDate AS PostCreated, 
       rp.Score AS PostScore, 
       rp.CommentCount AS TotalComments,
       (SELECT COUNT(DISTINCT l.RelatedPostId) 
        FROM PostLinks l 
        WHERE l.PostId = rp.Id) AS RelatedPostsCount
FROM UsersWithBadges up
JOIN RankedPosts rp ON up.UserId = rp.OwnerUserId 
JOIN Users u ON u.Id = up.UserId
WHERE up.BadgeCount > 5 
  AND rp.PostRank = 1
GROUP BY u.DisplayName, u.Reputation, u.AboutMe, up.BadgeCount, up.GoldCount, up.SilverCount, up.BronzeCount, rp.Title, rp.CreationDate, rp.Score, rp.CommentCount, rp.Id
ORDER BY u.Reputation DESC, rp.Score DESC;