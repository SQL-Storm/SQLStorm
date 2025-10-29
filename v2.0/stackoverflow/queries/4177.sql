-- {"query": "4177.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1803}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS total_posts,
      SUM(p.Score) AS total_score,
      AVG(p.CommentCount) AS avg_comment_count,
      MAX(p.CreationDate) AS latest_post_date
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  TopEditors AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS distinct_edited_posts,
      MAX(rpe.CreationDate) AS latest_edit_date
    FROM RankedPostEdits rpe
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
    HAVING
      COUNT(DISTINCT rpe.PostId) > 5
  )
SELECT
  u.Id AS user_id,
  u.DisplayName,
  u.Reputation,
  upa.total_posts,
  upa.total_score,
  upa.avg_comment_count,
  upa.latest_post_date,
  te.distinct_edited_posts,
  te.latest_edit_date,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS website_category,
  CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) AS BIGINT) / 86400 AS days_since_creation,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 1
  ) AS gold_badge_count,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 2
  ) AS silver_badge_count,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 3
  ) AS bronze_badge_count,
  COALESCE(
    (
      SELECT
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
      FROM Votes v
      WHERE
        v.UserId = u.Id
    ),
    0
  ) AS total_upvotes_given,
  COALESCE(
    (
      SELECT
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
      FROM Votes v
      WHERE
        v.UserId = u.Id
    ),
    0
  ) AS total_downvotes_given,
  CASE
    WHEN upa.latest_post_date > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') THEN 'Active'
    ELSE 'Inactive'
  END AS activity_status,
  CASE
    WHEN u.Views > 10000 THEN 'High Views'
    WHEN u.Views > 1000 THEN 'Medium Views'
    ELSE 'Low Views'
  END AS view_segment,
  ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, upa.total_posts DESC) AS reputation_rank,
  LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS previous_reputation
FROM Users u
LEFT JOIN UserPostActivity upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN TopEditors te
  ON u.Id = te.UserId
WHERE
  u.DisplayName IS NOT NULL
  AND u.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%'
  AND u.Location LIKE '%USA%'
  AND u.Views > 500
  AND u.Reputation BETWEEN 1000 AND 50000
  AND EXISTS (
    SELECT
      1
    FROM Posts p
    WHERE
      p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.ClosedDate IS NULL
  )
UNION
SELECT
  u.Id AS user_id,
  u.DisplayName,
  u.Reputation,
  upa.total_posts,
  upa.total_score,
  upa.avg_comment_count,
  upa.latest_post_date,
  te.distinct_edited_posts,
  te.latest_edit_date,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS website_category,
  CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) AS BIGINT) / 86400 AS days_since_creation,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 1
  ) AS gold_badge_count,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 2
  ) AS silver_badge_count,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 3
  ) AS bronze_badge_count,
  COALESCE(
    (
      SELECT
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
      FROM Votes v
      WHERE
        v.UserId = u.Id
    ),
    0
  ) AS total_upvotes_given,
  COALESCE(
    (
      SELECT
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
      FROM Votes v
      WHERE
        v.UserId = u.Id
    ),
    0
  ) AS total_downvotes_given,
  CASE
    WHEN upa.latest_post_date > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') THEN 'Active'
    ELSE 'Inactive'
  END AS activity_status,
  CASE
    WHEN u.Views > 10000 THEN 'High Views'
    WHEN u.Views > 1000 THEN 'Medium Views'
    ELSE 'Low Views'
  END AS view_segment,
  ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, upa.total_posts DESC) AS reputation_rank,
  LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS previous_reputation
FROM Users u
LEFT JOIN UserPostActivity upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN TopEditors te
  ON u.Id = te.UserId
WHERE
  u.DisplayName IS NOT NULL
  AND u.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%'
  AND u.Location LIKE '%Canada%'
  AND u.Views > 200
  AND u.Reputation BETWEEN 500 AND 10000
  AND NOT EXISTS (
    SELECT
      1
    FROM Posts p
    WHERE
      p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.ClosedDate IS NULL
  )
ORDER BY
  user_id;