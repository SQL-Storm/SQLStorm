-- {"query": "4045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2050}
WITH
  RankedPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_views,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_per_post,
      AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_per_post_type,
      SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS total_views_per_post_type,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS is_closed,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_post_score,
      p.Tags
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Comments c
        ON c.PostId = p.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1 AND p.CreationDate > DATE '2023-01-01'
  ),
  UserPostActivity AS (
    SELECT
      rp.OwnerUserId,
      COUNT(DISTINCT rp.Id) AS distinct_posts_owned,
      SUM(rp.Score) AS total_score_owned,
      AVG(rp.ViewCount) AS avg_views_owned,
      COUNT(DISTINCT c.Id) AS total_comments_made,
      MAX(rp.CreationDate) AS last_post_creation_date
    FROM
      RankedPosts rp
      LEFT JOIN Comments c
        ON rp.OwnerUserId = c.UserId
    GROUP BY
      rp.OwnerUserId
  ),
  HighEngagementUsers AS (
    SELECT
      up.OwnerUserId
    FROM
      UserPostActivity up
    WHERE
      up.distinct_posts_owned > 100
      AND up.total_score_owned > 5000
      AND up.avg_views_owned > 1000
      AND up.total_comments_made > 200
  )
SELECT
  rp.Id AS post_id,
  rp.PostTypeName,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.rn_score_views,
  rp.comment_count_per_post,
  rp.avg_score_per_post_type,
  rp.total_views_per_post_type,
  rp.is_closed,
  rp.previous_post_score,
  u.DisplayName AS owner_display_name,
  CASE
    WHEN u.Reputation > 10000 THEN 'HighRep'
    WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'MidRep'
    ELSE 'LowRep'
  END AS user_reputation_tier,
  CASE
    WHEN rp.ClosedDate IS NOT NULL AND rp.ClosedDate < (CAST('2024-10-01' AS date) - INTERVAL '365' DAY) THEN 'OldClosed'
    WHEN rp.ClosedDate IS NOT NULL THEN 'RecentClosed'
    ELSE 'Open'
  END AS post_status,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'HasDuplicateLink'
    ELSE 'NoDuplicateLink'
  END AS duplicate_link_status,
  COALESCE(u.WebsiteUrl, 'NoWebsite') AS user_website,
  LOWER(SUBSTRING(CAST(rp.OwnerUserId AS VARCHAR) FROM 1 FOR 3)) AS owner_id_prefix,
  CASE
    WHEN u.AccountId IS NULL THEN 'NoAccountId'
    ELSE CAST(u.AccountId AS VARCHAR)
  END AS user_account_id,
  CASE
    WHEN rp.Tags LIKE '%<sql>%' THEN TRUE
    ELSE FALSE
  END AS has_sql_tag,
  CASE
    WHEN rp.OwnerUserId IN (
      SELECT OwnerUserId
      FROM RankedPosts
      WHERE PostTypeId = 1 AND Score > 1000
    ) THEN 'HighScoreQuestionOwner'
    ELSE 'OtherOwner'
  END AS owner_quality_indicator,
  upu.distinct_posts_owned,
  upu.total_score_owned,
  upu.avg_views_owned,
  upu.total_comments_made,
  upu.last_post_creation_date,
  CASE
    WHEN rp.OwnerUserId IN (SELECT OwnerUserId FROM HighEngagementUsers) THEN TRUE
    ELSE FALSE
  END AS is_high_engagement_user
FROM
  RankedPosts rp
  LEFT JOIN Users u
    ON rp.OwnerUserId = u.Id
  LEFT JOIN UserPostActivity upu
    ON rp.OwnerUserId = upu.OwnerUserId
WHERE
  rp.Score > 0
  AND rp.ViewCount > 100
  AND rp.comment_count_per_post BETWEEN 1 AND 10
  AND rp.avg_score_per_post_type > 5
  AND rp.is_closed = 0
  AND rp.OwnerUserId IS NOT NULL
UNION ALL
SELECT
  rp.Id AS post_id,
  rp.PostTypeName,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.rn_score_views,
  rp.comment_count_per_post,
  rp.avg_score_per_post_type,
  rp.total_views_per_post_type,
  rp.is_closed,
  rp.previous_post_score,
  u.DisplayName AS owner_display_name,
  CASE
    WHEN u.Reputation > 10000 THEN 'HighRep'
    WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'MidRep'
    ELSE 'LowRep'
  END AS user_reputation_tier,
  CASE
    WHEN rp.ClosedDate IS NOT NULL AND rp.ClosedDate < (CAST('2024-10-01' AS date) - INTERVAL '365' DAY) THEN 'OldClosed'
    WHEN rp.ClosedDate IS NOT NULL THEN 'RecentClosed'
    ELSE 'Open'
  END AS post_status,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rp.Id AND pl.LinkTypeId = 3
    ) THEN 'HasDuplicateLink'
    ELSE 'NoDuplicateLink'
  END AS duplicate_link_status,
  COALESCE(u.WebsiteUrl, 'NoWebsite') AS user_website,
  LOWER(SUBSTRING(CAST(rp.OwnerUserId AS VARCHAR) FROM 1 FOR 3)) AS owner_id_prefix,
  CASE
    WHEN u.AccountId IS NULL THEN 'NoAccountId'
    ELSE CAST(u.AccountId AS VARCHAR)
  END AS user_account_id,
  CASE
    WHEN rp.Tags LIKE '%<database>%' THEN TRUE
    ELSE FALSE
  END AS has_database_tag,
  CASE
    WHEN rp.OwnerUserId IN (
      SELECT OwnerUserId
      FROM RankedPosts
      WHERE PostTypeId = 2 AND Score > 500
    ) THEN 'HighScoreAnswerOwner'
    ELSE 'OtherOwner'
  END AS owner_quality_indicator,
  upu.distinct_posts_owned,
  upu.total_score_owned,
  upu.avg_views_owned,
  upu.total_comments_made,
  upu.last_post_creation_date,
  CASE
    WHEN rp.OwnerUserId IN (SELECT OwnerUserId FROM HighEngagementUsers) THEN TRUE
    ELSE FALSE
  END AS is_high_engagement_user
FROM
  RankedPosts rp
  LEFT JOIN Users u
    ON rp.OwnerUserId = u.Id
  LEFT JOIN UserPostActivity upu
    ON rp.OwnerUserId = upu.OwnerUserId
WHERE
  rp.Score < 0
  AND rp.ViewCount < 50
  AND rp.comment_count_per_post > 5
  AND rp.is_closed = 1
  AND rp.ClosedDate IS NOT NULL
  AND rp.OwnerUserId IS NOT NULL;