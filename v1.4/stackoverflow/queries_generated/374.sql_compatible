WITH
  active_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, u.Location, u.WebsiteUrl
    FROM Users u
    WHERE u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days')
       OR u.Reputation > 1000
  ),
  user_metrics AS (
    SELECT
      au.Id,
      au.DisplayName,
      au.Reputation,
      au.LastAccessDate,
      au.Location,
      au.WebsiteUrl,
      (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = au.Id) AS TotalPosts,
      (SELECT COALESCE(SUM(p.Score), 0) FROM Posts p WHERE p.OwnerUserId = au.Id) AS SumPostScore,
      (SELECT COUNT(*) FROM Badges b WHERE b.UserId = au.Id) AS UserBadges,
      (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = au.Id) AS LastActiveDate
    FROM active_users au
  ),
  user_rank AS (
    SELECT
      um.*,
      ROW_NUMBER() OVER (
        ORDER BY
          (COALESCE(um.SumPostScore, 0) * 0.6) +
          (COALESCE(um.Reputation, 0) * 0.4) +
          (COALESCE(um.UserBadges, 0) * 0.2)
      ) AS rn
    FROM user_metrics um
  ),
  top_users AS (
    SELECT * FROM user_rank WHERE rn <= 120
  ),
  recent_posts_by_user AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.CreationDate,
      p.LastActivityDate,
      COALESCE(string_agg(DISTINCT t.TagName, ','), '') AS TagList,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS rn
    FROM Posts p
    LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    ) t ON true
    WHERE p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '60 days')
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate
  ),
  set_union AS (
    SELECT
      CAST('USER' AS TEXT) AS source_type,
      t.Id AS key_id,
      t.DisplayName AS name,
      CAST(t.Reputation AS TEXT) AS metric_a,
      CAST(t.SumPostScore AS TEXT) AS metric_b,
      CAST(t.TotalPosts AS TEXT) AS metric_c,
      CAST(t.UserBadges AS TEXT) AS metric_d,
      t.LastAccessDate,
      t.rn
    FROM top_users t
    UNION ALL
    SELECT
      CAST('POST' AS TEXT) AS source_type,
      rp.PostId AS key_id,
      rp.Title AS name,
      CAST(rp.Score AS TEXT) AS metric_a,
      CAST(rp.ViewCount AS TEXT) AS metric_b,
      CAST(rp.OwnerUserId AS TEXT) AS metric_c,
      rp.TagList AS metric_d,
      rp.LastActivityDate,
      rp.rn
    FROM recent_posts_by_user rp
  )
SELECT *
FROM set_union
ORDER BY source_type, metric_a DESC
LIMIT 100;