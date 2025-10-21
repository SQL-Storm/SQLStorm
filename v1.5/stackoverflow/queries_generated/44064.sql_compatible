WITH question_stats AS (
  SELECT p.Id,
         p.CreationDate,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount,
         p.ViewCount,
         p.Score,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views,
         (CAST(DATE_PART('day', AGE(p.CreationDate, TIMESTAMP '1970-01-01')) AS numeric) / 365.25) AS age_years,
         CASE WHEN p.ClosedDate IS NULL THEN 0 ELSE 1 END AS is_closed,
         CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS is_community_owned
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
answer_stats AS (
  SELECT p.ParentId,
         COUNT(*) AS answer_count
  FROM Posts p
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
badges_stats AS (
  SELECT b.UserId,
         COUNT(*) AS badge_count,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
  FROM Badges b
  GROUP BY b.UserId
)
SELECT q.Id,
       q.CreationDate,
       q.AnswerCount,
       q.CommentCount,
       q.FavoriteCount,
       q.ViewCount,
       q.Score,
       q.Reputation,
       q.UpVotes,
       q.DownVotes,
       q.Views,
       q.age_years,
       q.is_closed,
       q.is_community_owned,
       a.answer_count,
       b.badge_count,
       b.gold_badges,
       b.silver_badges,
       b.bronze_badges
FROM question_stats q
LEFT JOIN answer_stats a ON q.Id = a.ParentId
LEFT JOIN badges_stats b ON q.Reputation = b.UserId
ORDER BY q.CreationDate DESC
LIMIT 1000;