-- {"query": "14041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 693}
WITH cte AS (
  SELECT p.Id AS PostId, p.Title, p.CreationDate, p.OwnerUserId, 
         CASE WHEN p.ClosedDate IS NULL THEN 0 ELSE 1 END AS IsClosed,
         RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank
  FROM Posts p
  WHERE p.PostTypeId = 1
),
closed_posts AS (
  SELECT PostId, Title, CreationDate, OwnerUserId, IsClosed
  FROM cte
  WHERE IsClosed = 1
),
open_posts AS (
  SELECT PostId, Title, CreationDate, OwnerUserId, IsClosed
  FROM cte
  WHERE IsClosed = 0
),
user_stats AS (
  SELECT OwnerUserId, 
         SUM(CASE WHEN IsClosed = 1 THEN 1 ELSE 0 END) AS ClosedPostCount,
         SUM(CASE WHEN IsClosed = 0 THEN 1 ELSE 0 END) AS OpenPostCount,
         COUNT(*) AS TotalPostCount,
         MAX(ScoreRank) AS MaxScoreRank
  FROM cte
  GROUP BY OwnerUserId
)
SELECT u.DisplayName, 
       u.Reputation, 
       u.Location,
       u.Views,
       u.UpVotes,
       u.DownVotes,
       us.ClosedPostCount,
       us.OpenPostCount,
       us.TotalPostCount,
       us.MaxScoreRank,
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
       (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotes2,
       (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVotes2,
       (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
       (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (5, 6)) AS EditCount
FROM Users u
LEFT JOIN user_stats us ON u.Id = us.OwnerUserId
ORDER BY u.Reputation DESC
LIMIT 10;
