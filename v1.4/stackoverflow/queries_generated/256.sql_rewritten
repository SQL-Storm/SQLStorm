-- {"query": "256.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6876} 
WITH
post_tags AS (
  SELECT p.Id AS post_id,
         unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag_name
  FROM Posts p
  WHERE p.Tags IS NOT NULL
),
user_top_tags AS (
  SELECT u.Id AS user_id,
         pt.tag_name,
         COUNT(*) AS tag_count
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  JOIN post_tags pt ON pt.post_id = p.Id
  GROUP BY u.Id, pt.tag_name
),
user_top3_tags AS (
  SELECT user_id, string_agg(tag_name, ',') AS top_tags
  FROM (
    SELECT user_id, tag_name,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_count DESC) AS rn
    FROM user_top_tags
  ) s
  WHERE rn <= 3
  GROUP BY user_id
),
recent_counts AS (
  SELECT OwnerUserId AS user_id, COUNT(*) AS recent_post_count
  FROM Posts
  WHERE CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days'
  GROUP BY OwnerUserId
),
net_votes AS (
  SELECT p.OwnerUserId AS user_id,
         SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS net_votes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  GROUP BY p.OwnerUserId
),
badge_counts AS (
  SELECT UserId AS user_id, COUNT(*) AS badge_count, MAX(Date) AS last_badge
  FROM Badges
  GROUP BY UserId
),
latest_activity AS (
  SELECT OwnerUserId AS user_id, MAX(LastActivityDate) AS last_activity
  FROM Posts
  GROUP BY OwnerUserId
),
latest_title AS (
  SELECT u.Id AS user_id,
         (SELECT Title
          FROM Posts p
          WHERE p.OwnerUserId = u.Id
          ORDER BY p.LastActivityDate DESC NULLS LAST
          LIMIT 1) AS latest_title
  FROM Users u
)
SELECT
  u.Id AS user_id,
  u.DisplayName,
  COALESCE(rc.recent_post_count, 0) AS recent_posts_180d,
  COALESCE(nv.net_votes, 0) AS net_votes_365d,
  COALESCE(bc.badge_count, 0) AS badge_count,
  la.last_activity,
  lt.latest_title,
  COALESCE(ut.top_tags, '') AS top_tags
FROM Users u
LEFT JOIN recent_counts rc ON rc.user_id = u.Id
LEFT JOIN net_votes nv ON nv.user_id = u.Id
LEFT JOIN badge_counts bc ON bc.user_id = u.Id
LEFT JOIN latest_activity la ON la.user_id = u.Id
LEFT JOIN latest_title lt ON lt.user_id = u.Id
LEFT JOIN user_top3_tags ut ON ut.user_id = u.Id
WHERE u.Id > 0
ORDER BY u.Reputation DESC NULLS LAST
LIMIT 100;