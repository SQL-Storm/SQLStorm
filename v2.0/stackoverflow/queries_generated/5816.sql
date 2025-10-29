-- {"query": "5816.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1024} 
WITH
-- recentTopQuestions: questions with high activity and varied history for benchmarking
recentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
    AND (p.Score > 0 OR p.ViewCount > 100)
),
-- top tag proxies: derive tag influence via tag wiki/excerpt presence
tagInfluence AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    CASE
      WHEN t.ExcerptPostId IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS HasExcerpt,
    CASE
      WHEN t.WikiPostId IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS HasWiki
  FROM Tags t
  WHERE t.Count > 1000
),
-- correlated subquery: for each top question, count recent comments by its author and by others
authorActivity AS (
  SELECT
    r.PostId,
    r.OwnerUserId,
    (SELECT COUNT(*) FROM Comments c
     WHERE c.PostId = r.PostId
       AND c.UserId IS NOT NULL) AS CommentCountOnPost,
    (SELECT COUNT(*) FROM Comments c
     WHERE c.PostId = r.PostId
       AND c.UserId = r.OwnerUserId) AS OwnerCommentCount
  FROM recentTopQuestions r
),
-- windowed ranking: compute a composite score using multiple metrics
ranked AS (
  SELECT
    r.PostId,
    r.Title,
    r.Score,
    r.ViewCount,
    r.CreationDate,
    r.LastActivityDate,
    r.OwnerUserId,
    r.OwnerDisplayName,
    r.Tags,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    a.CommentCountOnPost,
    a.OwnerCommentCount,
    ROW_NUMBER() OVER (
      PARTITION BY DATE(r.CreationDate)
      ORDER BY
        r.Score * 2.0
        + r.ViewCount * 0.5
        + COALESCE(a.CommentCountOnPost,0) * 1.2
        + COALESCE(a.OwnerCommentCount,0) * 0.8
        - EXTRACT(epoch FROM (CURRENT_TIMESTAMP - r.LastActivityDate)) / 3600.0
      DESC
    ) AS rn
  FROM recentTopQuestions r
  LEFT JOIN authorActivity a
    ON r.PostId = a.PostId
),
-- final selection: combine with cross-join to a small set of tag influence samples
finalSet AS (
  SELECT
    rk.PostId,
    rk.Title,
    rk.Score,
    rk.ViewCount,
    rk.CreationDate,
    rk.LastActivityDate,
    rk.OwnerUserId,
    rk.OwnerDisplayName,
    rk.Tags,
    rk.AnswerCount,
    rk.CommentCount,
    rk.FavoriteCount,
    rk.CommentCountOnPost,
    rk.OwnerCommentCount,
    CASE
      WHEN t.TagName IS NOT NULL THEN t.TagName
      ELSE NULL
    END AS TopTag
  FROM ranked rk
  LEFT JOIN tagInfluence t
    ON rk.Tags LIKE '%' || t.TagName || '%'
  WHERE rk.rn <= 50
)
SELECT
  fs.PostId,
  fs.Title,
  fs.Score,
  fs.ViewCount,
  fs.CreationDate,
  fs.LastActivityDate,
  fs.OwnerUserId,
  fs.OwnerDisplayName,
  fs.Tags,
  fs.AnswerCount,
  fs.CommentCount,
  fs.FavoriteCount,
  fs.CommentCountOnPost,
  fs.OwnerCommentCount,
  fs.TopTag,
  -- a few derived metrics for benchmarking via JSON-like string assembly (PostHistory-like)
  CONCAT(
    '{"post":', fs.PostId,
    ', "owner":', COALESCE(fs.OwnerUserId, -1),
    ', "tag":', COALESCE(NULLIF(fs.TopTag, NULL), '"none"'),
    ', "score":', fs.Score,
    ', "activityHoursSinceLast":', EXTRACT(epoch FROM (CURRENT_TIMESTAMP - fs.LastActivityDate))/3600.0,
    ', "explicitNull":', CASE WHEN fs.OwnerDisplayName IS NULL THEN 'true' ELSE 'false' END,
    '}'
  ) AS BenchmarkPayload
FROM finalSet fs
ORDER BY fs.PostId;