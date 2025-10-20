-- {"query": "1052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 409} 

WITH UsersWithBadges AS (
    SELECT u.Id AS UserId, 
           u.DisplayName, 
           COUNT(b.Id) AS BadgeCount, 
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
RankedPosts AS (
    SELECT p.Id, 
           p.Title, 
           p.CreationDate, 
           p.Score, 
           COUNT(c.Id) AS CommentCount,
           DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year' 
      AND p.Score > 0
    GROUP BY p.Id
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
WHERE up.BadgeCount > 5 
  AND rp.PostRank = 1
ORDER BY up.Reputation DESC, rp.Score DESC;
