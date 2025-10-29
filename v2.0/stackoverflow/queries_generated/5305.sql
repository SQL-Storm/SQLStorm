-- {"query": "5305.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 627} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    uw.DisplayName AS LastEditorDisplayName,
    p.LastEditorUserId,
    p.LastEditDate,
    p.Body,
    -- Window function: cumulative sum of Score by day for Questions only
    SUM(CASE WHEN pt.Name = 'Question' THEN p.Score ELSE 0 END) OVER (PARTITION BY DATE(p.CreationDate) ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_daily_score
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users uw ON p.LastEditorUserId = uw.Id
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  -- correlate with recent badges of owner to simulate complex predicate
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
),
complex_pred AS (
  SELECT
    rp.*,
    -- correlated subquery: latest comment by owner on this post, if any
    (SELECT MAX(c.CreationDate)
     FROM Comments c
     WHERE c.PostId = rp.PostId AND c.UserId = rp.OwnerUserId) AS last_owner_comment_date,
    -- set operation: union with a synthetic row set to benchmark
    CASE
      WHEN rp.PostTypeId = 1 THEN 'Question'
      ELSE 'Other'
    END AS post_kind_label
  FROM ranked_posts rp
),
flatten AS (
  SELECT
    cp.*,
    -- complex predicate and NULL logic
    CASE
      WHEN cp.OwnerUserId IS NULL THEN 'Guest'
      WHEN cp.OwnerUserId = -1 THEN 'Community'
      ELSE COALESCE(cp.OwnerDisplayName, 'Unknown')
    END AS owner_label,
    -- string expression and calculations
    CONCAT('Post(', cp.PostId, '): ', COALESCE(cp.Title, ''), ' [', cp.Tags, ']') AS title_with_tags,
    -- a nested window: rank owners by reputation within each post type
    DENSE_RANK() OVER (PARTITION BY cp.PostTypeId ORDER BY cp.Reputation DESC, cp.CreationDate) AS rep_rank_within_type
  FROM complex_pred cp
)
SELECT
  *
FROM flatten
WHERE
  (PostTypeId = 1 AND CommentCount > 0)
  OR (PostTypeId = 2 AND ViewCount > 100)
ORDER BY
  rep_rank_within_type ASC,
  CreationDate DESC
LIMIT 100;