-- {"query": "241.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8234} 
WITH
UsersWithRecent AS (
  SELECT Id AS user_id,
         DisplayName AS user_name,
         Reputation
  FROM Users
  WHERE AccountId IS NOT NULL
),
UserPosts AS (
  SELECT
     u.user_id,
     u.user_name,
     u.Reputation,
     p.Id AS post_id,
     p.Title,
     p.Tags,
     p.Score,
     p.ViewCount,
     p.CreationDate,
     p.LastActivityDate,
     ROW_NUMBER() OVER (PARTITION BY u.user_id ORDER BY p.LastActivityDate DESC NULLS LAST, p.Score DESC) AS rn
  FROM UsersWithRecent u
  LEFT JOIN Posts p ON p.OwnerUserId = u.user_id AND p.PostTypeId = 1
)
SELECT
  user_id,
  user_name,
  Reputation,
  post_id,
  Title,
  Tags,
  Score,
  ViewCount,
  CreationDate,
  LastActivityDate,
  CASE WHEN post_id IS NULL THEN 'NO_POST' ELSE 'HAS_POST' END AS status,
  (SELECT ph.Comment
   FROM PostHistory ph
   WHERE ph.PostId = post_id
     AND ph.PostHistoryTypeId = 10
   ORDER BY ph.CreationDate DESC
   LIMIT 1) AS last_close_reason,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = post_id) AS comment_count,
  CONCAT('Score=', COALESCE(Score,0), ';Views=', COALESCE(ViewCount,0)) AS metrics_string,
  ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY LastActivityDate DESC NULLS LAST) AS rank
FROM UserPosts
WHERE rn = 1

UNION ALL

SELECT
  user_id,
  user_name,
  Reputation,
  NULL AS post_id,
  NULL AS Title,
  NULL AS Tags,
  NULL AS Score,
  NULL AS ViewCount,
  NULL AS CreationDate,
  NULL AS LastActivityDate,
  'NO_POST' AS status,
  NULL AS last_close_reason,
  NULL AS comment_count,
  CONCAT('UserReputation=', Reputation) AS metrics_string,
  1::bigint AS rank
FROM UsersWithRecent u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.user_id)

ORDER BY user_id, rank;