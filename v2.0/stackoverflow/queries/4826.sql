WITH
  RankedPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.PostTypeId
        ORDER BY
          p.Score DESC,
          p.ViewCount DESC
      ) AS rn_score_view,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS rn_creation_date
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS total_posts,
      SUM(p.Score) AS total_score,
      SUM(p.ViewCount) AS total_views
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  RecentPostActivity AS (
    SELECT
      p.Id,
      MAX(ph.CreationDate) AS last_history_date
    FROM Posts p
    JOIN PostHistory ph
      ON p.Id = ph.PostId
    WHERE
      ph.PostHistoryTypeId IN (2, 4, 5, 8)
    GROUP BY
      p.Id
  ),
  HighReputationUsers AS (
    SELECT
      Id
    FROM Users
    WHERE
      Reputation > 50000
  )
SELECT
  COALESCE(u.DisplayName, 'Deleted User') AS display_name,
  pt.Name AS post_type_name,
  rp.Score AS score,
  rp.AnswerCount AS answer_count,
  rp.CommentCount AS comment_count,
  rp.FavoriteCount AS favorite_count,
  rp.ViewCount AS view_count,
  COALESCE(rp.Score, 0) + COALESCE(rp.ViewCount, 0) * 10 AS weighted_score,
  CASE
    WHEN rp.rn_score_view <= 10 THEN 'Top 10 by Score/View'
    WHEN rp.rn_creation_date <= 50 THEN 'Top 50 by Creation'
    ELSE 'Other'
  END AS ranking_category,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = u.Id AND b.Name LIKE '%Expert%'
    ) THEN 'Has Expert Badge'
    ELSE 'No Expert Badge'
  END AS badge_status,
  CAST(EXTRACT(epoch FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) AS days_since_creation,
  (COALESCE(upc.total_posts, 0) || ' posts, ' || COALESCE(upc.total_score, 0) || ' score, ' || COALESCE(upc.total_views, 0) || ' views') AS user_contribution_summary,
  CASE
    WHEN rpa.last_history_date IS NULL THEN 'No significant edit history'
    WHEN EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - rpa.last_history_date)) < 3600 * 24 THEN 'Edited in last 24 hours'
    WHEN EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - rpa.last_history_date)) < 3600 * 24 * 7 THEN 'Edited in last week'
    ELSE 'Edited more than a week ago'
  END AS edit_recency,
  CASE
    WHEN u.Id IN (SELECT Id FROM HighReputationUsers) THEN 'High Reputation'
    ELSE 'Standard Reputation'
  END AS reputation_level,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'Is a Duplicate Link'
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.RelatedPostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'Is Linked To As Duplicate'
    ELSE 'No Duplicate Link Association'
  END AS duplicate_status,
  rp.rn_score_view,
  rp.rn_creation_date,
  rp.Id,
  rp.OwnerUserId,
  p.PostTypeId,
  u.CreationDate
FROM RankedPosts rp
JOIN Posts p
  ON rp.Id = p.Id
LEFT JOIN Users u
  ON rp.OwnerUserId = u.Id
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN UserPostCounts upc
  ON rp.OwnerUserId = upc.OwnerUserId
LEFT JOIN RecentPostActivity rpa
  ON rp.Id = rpa.Id
WHERE
  rp.rn_score_view <= 100
  AND rp.rn_creation_date <= 200
  AND rp.Score > 5
  AND EXTRACT(YEAR FROM AGE(TIMESTAMP '2024-10-01 12:34:56', u.CreationDate)) > 0
ORDER BY
  rp.Score DESC,
  rp.ViewCount DESC
LIMIT 1000;