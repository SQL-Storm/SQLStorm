WITH
  RelevantPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL
        THEN CAST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.ClosedDate)) / 86400 AS INTEGER)
        ELSE NULL
      END AS DaysSinceClosed,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type_date,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_per_post
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.OwnerUserId IS NOT NULL
      AND u.Reputation > 1000
  ),
  PostLinkAnalysis AS (
    SELECT
      pl.PostId,
      COUNT(pl.RelatedPostId) AS num_linked_posts
    FROM PostLinks pl
    WHERE
      pl.LinkTypeId = 1
    GROUP BY
      pl.PostId
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS total_posts_by_user,
      SUM(p.Score) AS total_score_by_user,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS avg_score_by_user,
      MAX(p.CreationDate) AS last_post_date_by_user
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  ComplexCalculations AS (
    SELECT
      rp.Id,
      rp.PostTypeId,
      rp.PostTypeName,
      rp.OwnerUserId,
      rp.OwnerDisplayName,
      rp.CreationDate,
      rp.Score,
      rp.AnswerCount,
      rp.CommentCount,
      rp.FavoriteCount,
      rp.ViewCount,
      rp.ClosedDate,
      rp.DaysSinceClosed,
      rp.avg_score_by_type,
      rp.comment_count_per_post,
      COALESCE(pla.num_linked_posts, 0) AS num_linked_posts,
      upa.total_posts_by_user,
      upa.total_score_by_user,
      upa.avg_score_by_user,
      upa.last_post_date_by_user,
      CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'High Performer'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Low Performer'
        ELSE 'Average Performer'
      END AS performance_tier,
      CASE
        WHEN rp.FavoriteCount > 10 AND rp.CommentCount > 5 THEN 'Engaging'
        WHEN rp.AnswerCount > 3 AND rp.Score > 5 THEN 'Popular'
        ELSE 'Standard'
      END AS engagement_level,
      (rp.OwnerDisplayName || ' (' || rp.OwnerUserId || ')') AS owner_identifier,
      (rp.ViewCount * 1.0 / NULLIF(rp.CommentCount, 0)) AS views_per_comment,
      CASE WHEN rp.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS post_status
    FROM RelevantPosts rp
    LEFT JOIN PostLinkAnalysis pla
      ON rp.Id = pla.PostId
    LEFT JOIN UserPostActivity upa
      ON rp.OwnerUserId = upa.OwnerUserId
    WHERE
      rp.rn_by_type_date <= 100
  )
SELECT
  cc.Id,
  cc.PostTypeId,
  cc.PostTypeName,
  cc.OwnerUserId,
  cc.OwnerDisplayName,
  cc.CreationDate,
  cc.Score,
  cc.AnswerCount,
  cc.CommentCount,
  cc.FavoriteCount,
  cc.ViewCount,
  cc.ClosedDate,
  cc.DaysSinceClosed,
  cc.avg_score_by_type,
  cc.comment_count_per_post,
  cc.num_linked_posts,
  cc.total_posts_by_user,
  cc.total_score_by_user,
  cc.avg_score_by_user,
  cc.last_post_date_by_user,
  cc.performance_tier,
  cc.engagement_level,
  cc.owner_identifier,
  cc.views_per_comment,
  cc.post_status,
  CASE
    WHEN cc.OwnerUserId IS NULL THEN 'Unknown'
    WHEN cc.OwnerDisplayName IS NULL THEN 'Anonymous'
    ELSE cc.OwnerDisplayName
  END AS display_name_logic,
  CASE
    WHEN cc.Score > 1000 THEN 'Highly Rated'
    WHEN cc.Score BETWEEN 100 AND 1000 THEN 'Moderately Rated'
    WHEN cc.Score > 0 THEN 'Slightly Rated'
    ELSE 'No Score'
  END AS score_categorization,
  CASE
    WHEN cc.AnswerCount > cc.CommentCount * 2 THEN 'More Answers than Comments'
    WHEN cc.CommentCount > cc.AnswerCount * 2 THEN 'More Comments than Answers'
    ELSE 'Balanced Activity'
  END AS activity_ratio,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cc.Id AND c.Score < 0) AS negative_comments_count,
  (UPPER(SUBSTRING(cc.PostTypeName FROM 1 FOR 1)) || SUBSTRING(cc.PostTypeName FROM 2 FOR CHAR_LENGTH(cc.PostTypeName) - 1)) AS formatted_post_type_name
FROM ComplexCalculations cc
WHERE
  cc.ViewCount > 100
  OR cc.FavoriteCount > 5
UNION ALL
SELECT
  NULL AS Id,
  0 AS PostTypeId,
  'Total Summary' AS PostTypeName,
  NULL AS OwnerUserId,
  NULL AS OwnerDisplayName,
  NULL AS CreationDate,
  SUM(Score) AS Score,
  SUM(AnswerCount) AS AnswerCount,
  SUM(CommentCount) AS CommentCount,
  SUM(FavoriteCount) AS FavoriteCount,
  SUM(ViewCount) AS ViewCount,
  NULL AS ClosedDate,
  NULL AS DaysSinceClosed,
  AVG(avg_score_by_type) AS avg_score_by_type,
  NULL AS comment_count_per_post,
  SUM(num_linked_posts) AS num_linked_posts,
  SUM(total_posts_by_user) AS total_posts_by_user,
  SUM(total_score_by_user) AS total_score_by_user,
  AVG(avg_score_by_user) AS avg_score_by_user,
  NULL AS last_post_date_by_user,
  NULL AS performance_tier,
  NULL AS engagement_level,
  NULL AS owner_identifier,
  AVG(views_per_comment) AS views_per_comment,
  NULL AS post_status,
  NULL AS display_name_logic,
  NULL AS score_categorization,
  NULL AS activity_ratio,
  NULL AS negative_comments_count,
  NULL AS formatted_post_type_name
FROM ComplexCalculations;