-- {"query": "52063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 257} 
WITH tagged_posts AS (
  SELECT p.Id AS post_id, p.OwnerUserId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
),
tag_user_upvotes AS (
  SELECT tp.tag_name, tp.OwnerUserId, COUNT(v.Id) AS upvotes, COUNT(DISTINCT tp.post_id) AS post_count
  FROM tagged_posts tp
  LEFT JOIN Votes v ON tp.post_id = v.PostId AND v.VoteTypeId = 2
  GROUP BY tp.tag_name, tp.OwnerUserId
),
ranked AS (
  SELECT tag_name, OwnerUserId, upvotes, post_count, RANK() OVER (PARTITION BY tag_name ORDER BY upvotes DESC, post_count DESC) AS rnk
  FROM tag_user_upvotes
)
SELECT r.tag_name, u.DisplayName, r.upvotes, r.post_count
FROM ranked r
JOIN Users u ON r.OwnerUserId = u.Id
WHERE r.rnk = 1
ORDER BY r.upvotes DESC, r.post_count DESC
LIMIT 100;