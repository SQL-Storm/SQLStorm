-- {"query": "5537.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 785} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    -- window: sum of views over 100-day window per user
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId
                                                               ORDER BY p.CreationDate
                                                               ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS UserUpvotesInWindow,
    -- correlated subquery: count of comments on the same tag as post (approx)
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveCommentCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- Questions
),
cte_metalog AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.ViewCount,
    rp.Score,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.Tags,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.UserUpvotesInWindow,
    rp.PositiveCommentCount,
    -- compute a complex synthetic metric combining several columns
    (rp.ViewCount * 2 +
     rp.Score * 10 +
     COALESCE(rp.FavoriteCount,0) * 50 +
     COALESCE(rp.CommentCount,0) * 5) AS CompositeMetric
  FROM ranked_posts rp
),
filtered AS (
  SELECT
    m.*,
    -- complex predicate with NULL handling and string expressions
    CASE
      WHEN m.OwnerReputation IS NULL THEN 0
      ELSE m.OwnerReputation
    END AS Rept,
    CASE
      WHEN m.Tags ~ '[<>]' THEN m.Tags -- ensure string expression used
      ELSE CONCAT('<', m.Tags, '>')
    END AS TagsEnvelope
  FROM cte_metalog m
  WHERE
    m.CompositeMetric > 1000
    AND (m.OwnerUserId IS NOT NULL AND m.OwnerUserId <> -1)
    AND (POSITION('<' IN m.Tags) = 0 OR m.Tags IS NULL)
),
final AS (
  SELECT
    f.Id,
    f.Title,
    f.ViewCount,
    f.Score,
    f.CreationDate,
    f.LastActivityDate,
    f.OwnerUserId,
    f.OwnerDisplayName,
    f.OwnerReputation,
    f.TagsEnvelope AS TagsFormatted,
    f.CommentCount,
    f.AnswerCount,
    f.FavoriteCount,
    f.ParentId,
    f.AcceptedAnswerId,
    f.UserUpvotesInWindow,
    f.PositiveCommentCount,
    f.CompositeMetric,
    -- windowed rank over composite metric by creation date
    DENSE_RANK() OVER (
      PARTITION BY DATE(f.CreationDate)
      ORDER BY f.CompositeMetric DESC
    ) AS DailyMetricRank
  FROM filtered f
)
SELECT
  *
FROM final
ORDER BY CompositeMetric DESC
LIMIT 100;