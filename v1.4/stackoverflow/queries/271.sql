-- {"query": "271.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 11788} 
WITH vote_agg AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes
  GROUP BY PostId
),
per_post AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         p.Title,
         p.PostTypeId,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.LastActivityDate,
         COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0) AS NetVotes
  FROM Posts p
  LEFT JOIN vote_agg v ON v.PostId = p.Id
  WHERE p.ClosedDate IS NULL
),
top_per_user AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY OwnerUserId, PostTypeId ORDER BY Score DESC, ViewCount DESC) AS rn
  FROM per_post
),
top_user_post AS (
  SELECT *
  FROM top_per_user
  WHERE rn = 1
),
latest_badge AS (
  SELECT UserId, Name AS badge_name, Date AS badge_date
  FROM (
     SELECT UserId, Name, Date,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date DESC) AS rn
     FROM Badges
  ) b
  WHERE rn = 1
),
tag_map AS (
  SELECT p.Id AS PostId,
         string_agg(t.tag, ',') AS tags
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
  GROUP BY p.Id
)
SELECT
  u.Id AS user_id,
  u.DisplayName,
  u.Reputation,
  u.Location,
  lb.badge_name AS last_badge_name,
  lb.badge_date AS last_badge_date,
  pt.Name AS post_type_name,
  tup.PostId,
  tup.Title,
  tup.Score,
  tup.ViewCount,
  tup.CreationDate,
  tup.LastActivityDate,
  tup.NetVotes,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tup.PostId) AS comment_count_on_top_post,
  tm.tags AS top_post_tags
FROM top_user_post tup
LEFT JOIN Users u ON u.Id = tup.OwnerUserId
LEFT JOIN latest_badge lb ON lb.UserId = u.Id
LEFT JOIN PostTypes pt ON pt.Id = tup.PostTypeId
LEFT JOIN tag_map tm ON tm.PostId = tup.PostId
ORDER BY u.Reputation DESC NULLS LAST, u.Id
LIMIT 100;