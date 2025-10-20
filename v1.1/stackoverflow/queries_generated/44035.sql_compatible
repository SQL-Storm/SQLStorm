WITH top_posts AS (
  SELECT p.Id, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions only
  ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
  LIMIT 1000
),
user_activity AS (
  SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
         COUNT(p.Id) AS total_posts,
         SUM(p.Score) AS total_score,
         SUM(p.ViewCount) AS total_views,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS total_upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS total_downvotes,
         COUNT(DISTINCT b.Id) AS total_badges
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v ON p.Id = v.PostId AND u.Id = v.UserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
post_comments AS (
  SELECT p.Id AS post_id, COUNT(c.Id) AS comment_count
  FROM Posts p
  LEFT JOIN Comments c ON p.Id = c.PostId
  GROUP BY p.Id
),
post_links AS (
  SELECT p.Id AS post_id, COUNT(pl.Id) AS link_count
  FROM Posts p
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  GROUP BY p.Id
),
post_history AS (
  SELECT p.Id AS post_id, COUNT(ph.Id) AS history_count
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId
  GROUP BY p.Id
)
SELECT
  tp.Id AS post_id,
  tp.CreationDate AS post_creation_date,
  tp.Score AS post_score,
  tp.ViewCount AS post_views,
  tp.OwnerUserId AS post_owner_user_id,
  tp.LastActivityDate AS post_last_activity_date,
  ua.Id AS user_id,
  ua.DisplayName AS user_display_name,
  ua.Reputation AS user_reputation,
  ua.CreationDate AS user_creation_date,
  ua.LastAccessDate AS user_last_access_date,
  ua.total_posts AS user_total_posts,
  ua.total_score AS user_total_score,
  ua.total_views AS user_total_views,
  ua.total_upvotes AS user_total_upvotes,
  ua.total_downvotes AS user_total_downvotes,
  ua.total_badges AS user_total_badges,
  pc.comment_count AS post_comment_count,
  pl.link_count AS post_link_count,
  ph.history_count AS post_history_count
FROM top_posts tp
JOIN user_activity ua ON tp.OwnerUserId = ua.Id
LEFT JOIN post_comments pc ON tp.Id = pc.post_id
LEFT JOIN post_links pl ON tp.Id = pl.post_id
LEFT JOIN post_history ph ON tp.Id = ph.post_id
ORDER BY tp.Score DESC, tp.ViewCount DESC, tp.LastActivityDate DESC;