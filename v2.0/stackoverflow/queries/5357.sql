WITH recent_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_cnt,
    AVG(p.Score) AS avg_post_score,
    MAX(p.ViewCount) AS max_views
  FROM Posts p
  JOIN Posts q ON p.Id = q.ParentId OR p.Id = q.Id
  JOIN Tags t ON t.Id = CAST(p.Tags AS INTEGER)
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
  GROUP BY t.TagName
),
high_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    COALESCE(COUNT(comm.Id), 0) AS CommentCount,
    ARRAY_AGG(vt.Name) FILTER (WHERE v.VoteTypeId IS NOT NULL) AS vote_types
  FROM Posts p
  LEFT JOIN Comments comm ON comm.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
  GROUP BY
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate
),
advanced_calc AS (
  SELECT
    hi.PostId,
    hi.Title,
    hi.OwnerUserId,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    hi.Score,
    hi.ViewCount,
    hi.CommentCount,
    hi.vote_types,
    CASE
      WHEN u.Reputation > 10000 THEN 'Elite'
      WHEN u.Reputation > 1000 THEN 'Pro'
      ELSE 'Newbie'
    END AS user_tier,
    ROW_NUMBER() OVER (PARTITION BY hi.OwnerUserId ORDER BY hi.Score DESC, hi.ViewCount DESC) AS rn_by_owner
  FROM high_activity hi
  LEFT JOIN Users u ON u.Id = hi.OwnerUserId
  WHERE hi.OwnerUserId IS NOT NULL
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerUserId,
  a.DisplayName,
  a.Reputation,
  a.user_tier,
  a.Score,
  a.ViewCount,
  a.CommentCount,
  a.vote_types,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = a.PostId) AS related_links,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.PostId) AS total_comments,
  (SELECT MIN(p.CreationDate) FROM Posts p WHERE p.Id = a.PostId) AS first_seen,
  (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = a.PostId) AS last_vote_date,
  (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = a.OwnerUserId) AS avg_owner_post_score,
  (SELECT AVG(p3.ViewCount) FROM Posts p3 WHERE p3.OwnerUserId = a.OwnerUserId) AS avg_owner_views,
  a.rn_by_owner
FROM advanced_calc a
WHERE a.rn_by_owner = 1
  AND a.Reputation IS NOT NULL
GROUP BY
  a.PostId,
  a.Title,
  a.OwnerUserId,
  a.DisplayName,
  a.Reputation,
  a.user_tier,
  a.Score,
  a.ViewCount,
  a.CommentCount,
  a.vote_types,
  a.rn_by_owner
ORDER BY a.user_tier, a.Score DESC, a.ViewCount DESC
LIMIT 100;