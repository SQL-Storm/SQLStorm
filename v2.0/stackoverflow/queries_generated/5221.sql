-- {"query": "5221.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 758} 
WITH ranked_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    -- overlap of user reputation with post score
    u.Reputation,
    -- window function: rank questions by score per day
    ROW_NUMBER() OVER (
      PARTITION BY DATE(p.CreationDate)
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_day,
    -- cumulative sum of views over last 7 days per user
    SUM(p.ViewCount) OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_views
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
extended AS (
  SELECT
    rq.*,
    -- correlated subquery: number of answers for this question
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = rq.PostId AND a.PostTypeId = 2) AS answer_count,
    -- correlated subquery: number of comments on this question
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS comment_count_q
  FROM ranked_questions rq
)
SELECT
  e.PostId,
  e.Title,
  e.Tags,
  e.CreationDate,
  e.LastActivityDate,
  e.Score,
  e.ViewCount,
  e.OwnerUserId,
  e.OwnerDisplayName,
  e.AnswerCount,
  e.CommentCount,
  e.FavoriteCount,
  e.Reputation,
  e.rolling_7d_views,
  e.rn_day,
  e.answer_count AS explicit_answer_count,
  e.comment_count_q AS explicit_comment_count,
  -- compute a complex metric: engagement density = (answers + comments) / (views + 1)
  (COALESCE(e.answer_count, 0) + COALESCE(e.comment_count_q, 0))::numeric / (e.ViewCount + 1) AS engagement_density,
  -- string expression: normalized title length and a tag-derived hash-like value
  (LENGTH(e.Title) * 1.0 / NULLIF(LENGTH(REPLACE(e.Title, ' ', '')), 0)) AS title_word_density,
  md5(e.Tags) AS tags_hash,
  -- null-safe conditional: posts with high reputation and high score
  CASE
    WHEN e.Reputation IS NULL THEN 'unknown'
    WHEN e.Reputation > 10000 AND e.Score > 50 THEN 'stellar'
    WHEN e.Reputation > 1000 AND e.Score > 20 THEN 'strong'
    ELSE 'regular'
  END AS categorization
FROM extended e
JOIN PostLinks pl ON pl.PostId = e.PostId
LEFT JOIN Votes v ON v.PostId = e.PostId
WHERE
  EXISTS (
    SELECT 1
    FROM PostHistory ph
    WHERE ph.PostId = e.PostId
      AND ph.PostHistoryTypeId IN (16, 50) -- Community Owned / CommunityBump signals
  )
ORDER BY
  e.rolling_7d_views DESC,
  e.Score DESC,
  e.LastActivityDate DESC
LIMIT 100;