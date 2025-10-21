WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.Title, p.Body, p.OwnerUserId, p.LastEditDate, p.CreationDate, p.Tags, p.ViewCount, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
         CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE NULL END AS AcceptedAnswerId,
         CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE NULL END AS ParentId,
         CASE WHEN p.PostTypeId = 1 THEN ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) ELSE NULL END AS UserQuestionRank
  FROM Posts p
),
user_badges AS (
  SELECT b.UserId, COUNT(*) AS TotalBadges, SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
user_votes AS (
  SELECT v.UserId, COUNT(*) AS TotalVotes, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
  FROM Votes v
  GROUP BY v.UserId
),
datediff_seconds AS (
  SELECT EXTRACT(EPOCH FROM (LAST_EDIT - CREATION)) AS delta_secs
  FROM (
    SELECT MIN(p.LastEditDate) AS LAST_EDIT, MIN(p.CreationDate) AS CREATION
    FROM Posts p
  ) s
)
SELECT c.Id, c.PostTypeId, c.Title, c.Body, c.OwnerUserId, u.DisplayName, u.Reputation, u.AccountId, u.Views, u.UpVotes, u.DownVotes, ub.TotalBadges, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, uv.TotalVotes, uv.UpVotes AS UserUpVotes, uv.DownVotes AS UserDownVotes, uv.FavoriteVotes,
       CASE WHEN c.ClosedDate IS NOT NULL THEN 'Closed' WHEN c.CommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE 'Open' END AS PostStatus,
       CASE WHEN c.PostTypeId = 1 THEN c.AcceptedAnswerId WHEN c.PostTypeId = 2 THEN c.ParentId ELSE NULL END AS RelatedPostId,
       CASE WHEN c.PostTypeId = 1 THEN c.UserQuestionRank ELSE NULL END AS UserQuestionRank,
       SUBSTRING(c.Tags, 2, CHAR_LENGTH(c.Tags) - 2) AS PostTags,
       CONCAT(ROUND(NULLIF(c.ViewCount, 0) * 1.0 / NULLIF(CAST((SELECT delta_secs FROM datediff_seconds) AS NUMERIC) , 0), 2), ' views/day') AS ViewsPerDay,
       CONCAT(ROUND(NULLIF(c.Score, 0) * 1.0 / NULLIF(CAST((SELECT delta_secs FROM datediff_seconds) AS NUMERIC) , 0), 2), ' score/day') AS ScorePerDay,
       CONCAT(ROUND(NULLIF(c.CommentCount, 0) * 1.0 / NULLIF(CAST((SELECT delta_secs FROM datediff_seconds) AS NUMERIC) , 0), 2), ' comments/day') AS CommentsPerDay,
       CONCAT(ROUND(NULLIF(c.FavoriteCount, 0) * 1.0 / NULLIF(CAST((SELECT delta_secs FROM datediff_seconds) AS NUMERIC) , 0), 2), ' favorites/day') AS FavoritesPerDay
FROM cte c
JOIN Users u ON c.OwnerUserId = u.Id
LEFT JOIN user_badges ub ON c.OwnerUserId = ub.UserId
LEFT JOIN user_votes uv ON c.OwnerUserId = uv.UserId
ORDER BY c.Id;