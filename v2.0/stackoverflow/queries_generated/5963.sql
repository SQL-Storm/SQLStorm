-- {"query": "5963.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 819} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    -- window functions: rank by activity within per day
    ROW_NUMBER() OVER (PARTITION BY CAST(p.CreationDate AS date)
                       ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_per_day,
    -- cumulative sum of views over last 30 days per post owner
    SUM(p.ViewCount) OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate
      ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) AS rolling_30_day_views
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.DeletionDate IS NULL OR p.DeletionDate > NOW()
),
TopQuestions AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.rn_per_day,
    rp.rolling_30_day_views,
    -- correlated subquery: number of tags present in the post's tag list that match existing tags in Tags table
    (SELECT COUNT(*) FROM unnest(string_to_array(rp.Tags, '>')) AS t
     JOIN Tags tg ON lower(t), lower(t.TagName) = TRUE) AS tag_match_count
  FROM RankedPosts rp
  WHERE rp.PostTypeId = 1 -- questions
    AND rp.rn_per_day = 1
),
RecentLowActivity AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.Tags,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    tq.OwnerUserId,
    tq.LastActivityDate,
    tq.CommentCount,
    tq.AnswerCount,
    tq.FavoriteCount,
    tq.rolling_30_day_views,
    tq.tag_match_count,
    -- value expressions: compute a composite score using NULL-safe arithmetic
    COALESCE(tq.Score,0) * 2
      + COALESCE(tq.ViewCount,0) * 0.5
      + COALESCE(tq.AnswerCount,0) * 3
      + COALESCE(tq.tag_match_count,0) * 4
      + CASE WHEN tq.LastActivityDate IS NULL THEN 0 ELSE 1 END AS composite_score
  FROM TopQuestions tq
  WHERE tq.rolling_30_day_views IS NOT NULL
    AND tq.TagMatchCount IS NULL
)
SELECT
  rls.PostId,
  rls.Title,
  rls.Tags,
  rls.CreationDate,
  rls.Score,
  rls.ViewCount,
  rls.OwnerUserId,
  rls.LastActivityDate,
  rls.CommentCount,
  rls.AnswerCount,
  rls.FavoriteCount,
  rls.rolling_30_day_views,
  rls.tag_match_count,
  rls.composite_score,
  -- outer join: include last editor info if available
  u.DisplayName AS OwnerDisplayName,
  lu.DisplayName AS LastEditorDisplayName
FROM RecentLowActivity rls
LEFT JOIN Users u ON rls.OwnerUserId = u.Id
LEFT JOIN Posts p_last ON p_last.Id = rls.PostId
LEFT JOIN Users lu ON p_last.LastEditorUserId = lu.Id
ORDER BY rls.composite_score DESC, rls.LastActivityDate DESC
LIMIT 100;