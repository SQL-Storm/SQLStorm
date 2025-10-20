-- {"query": "54023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 988} 
WITH recent_posts AS (
    SELECT p.Id, p.OwnerUserId, p.Score, p.Tags
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
      AND p.PostTypeId = 1
),
tags_expanded AS (
    SELECT rp.OwnerUserId,
           trim(both '<>' FROM t.tag) AS tag,
           rp.Score
    FROM recent_posts rp
    CROSS JOIN LATERAL regexp_split_to_table(rp.Tags, '\>\<') AS t(tag)
),
agg AS (
    SELECT OwnerUserId,
           tag,
           COUNT(*) AS post_count,
           AVG(Score) AS avg_score
    FROM tags_expanded
    GROUP BY OwnerUserId, tag
),
ranked AS (
    SELECT a.OwnerUserId,
           a.tag,
           a.avg_score,
           a.post_count,
           ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.avg_score DESC) AS rn
    FROM agg a
),
user_stats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
    FROM Users u
)
SELECT us.UserId,
       us.DisplayName,
       us.Reputation,
       us.BadgeCount,
       r.tag,
       r.avg_score,
       r.post_count
FROM user_stats us
JOIN ranked r ON us.UserId = r.OwnerUserId
WHERE r.rn <= 5
ORDER BY us.UserId, r.avg_score DESC;