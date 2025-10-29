-- {"query": "5541.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 946}
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS rn
  FROM Users u
),
recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    -- replaced invalid/nonstandard column name p.CloseReasonTypes_Id if it exists in source schema it should be referenced correctly;
    -- otherwise omit to avoid error
    NULL AS CloseReasonTypes_Id
  FROM Posts p
  LEFT JOIN (SELECT 1 AS dummy) l ON TRUE
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
popular_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 1000
),
combined AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate AS PostDate,
    rp.Score AS PostScore,
    rp.ViewCount,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY rp.LastActivityDate DESC) AS recent_rank
  FROM top_users tu
  LEFT JOIN recent_posts rp
    ON rp.OwnerUserId = tu.UserId
  WHERE tu.rn <= 500
),
stat_window AS (
  SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.PostId,
    c.Title,
    c.PostDate,
    c.PostScore,
    c.ViewCount,
    c.LastActivityDate,
    c.PostTypeId,
    c.AcceptedAnswerId,
    c.ParentId,
    c.CommentCount,
    SUM(c.PostScore) OVER (PARTITION BY c.UserId ORDER BY c.PostDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_score_6,
    AVG(c.ViewCount) OVER (PARTITION BY c.UserId) AS avg_views_per_post
  FROM combined c
  WHERE c.recent_rank = 1
),
complex_expr AS (
  SELECT
    sw.UserId,
    sw.DisplayName,
    sw.Reputation,
    sw.PostId,
    sw.Title,
    sw.PostDate,
    sw.PostScore,
    sw.ViewCount,
    sw.LastActivityDate,
    sw.PostTypeId,
    sw.AcceptedAnswerId,
    sw.ParentId,
    sw.CommentCount,
    (sw.PostScore * 2 + sw.CommentCount) AS engagement_score,
    CASE
      WHEN sw.PostTypeId = 1 THEN 'Question'
      WHEN sw.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS post_kind,
    (sw.rolling_score_6 + sw.avg_views_per_post) AS composite_metric
  FROM stat_window sw
  WHERE sw.rolling_score_6 IS NOT NULL
)
SELECT
  ce.UserId,
  ce.DisplayName,
  ce.Reputation,
  ce.PostId,
  ce.Title,
  ce.post_kind,
  ce.PostDate,
  ce.PostScore,
  ce.ViewCount,
  ce.LastActivityDate,
  ce.AcceptedAnswerId,
  ce.ParentId,
  ce.CommentCount,
  ce.engagement_score,
  ce.composite_metric,
  last_post.p1_id,
  last_post.p1_title,
  last_post.p1_tags,
  last_post.p1_score,
  pl.PostId AS PostLink_PostId,
  pl.RelatedPostId AS PostLink_RelatedPostId,
  t.TagName AS RelatedTagName,
  t.Count AS RelatedTagCount
FROM complex_expr ce
JOIN LATERAL (
  SELECT
    p1.Id AS p1_id,
    p1.Title AS p1_title,
    p1.Tags AS p1_tags,
    p1.Score AS p1_score,
    p1.LastActivityDate AS p1_lastactivity
  FROM Posts p1
  WHERE p1.OwnerUserId = ce.UserId
  ORDER BY p1.LastActivityDate DESC
  LIMIT 1
) AS last_post ON TRUE
LEFT JOIN PostLinks pl ON pl.PostId = ce.PostId
LEFT JOIN Tags t ON t.ExcerptPostId = ce.PostId OR t.WikiPostId = ce.PostId
WHERE ce.composite_metric > 50
GROUP BY
  ce.UserId,
  ce.DisplayName,
  ce.Reputation,
  ce.PostId,
  ce.Title,
  ce.post_kind,
  ce.PostDate,
  ce.PostScore,
  ce.ViewCount,
  ce.LastActivityDate,
  ce.AcceptedAnswerId,
  ce.ParentId,
  ce.CommentCount,
  ce.engagement_score,
  ce.composite_metric,
  last_post.p1_id,
  last_post.p1_title,
  last_post.p1_tags,
  last_post.p1_score,
  pl.PostId,
  pl.RelatedPostId,
  t.TagName,
  t.Count
ORDER BY ce.Reputation DESC, ce.PostDate DESC
LIMIT 100;