WITH recent_posts AS (
    SELECT p.Id, p.OwnerUserId, p.Score, p.Tags
    FROM Posts p
    WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
      AND p.PostTypeId = 1
),
tags_expanded AS (
    SELECT rp.OwnerUserId,
           TRIM(BOTH '<>' FROM t.tag) AS tag,
           rp.Score
    FROM recent_posts rp
    CROSS JOIN LATERAL (
        SELECT TRIM(value) AS tag
        FROM (
            SELECT unnest(string_to_array(rp.Tags, '><')) AS value
        ) AS s
    ) AS t
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