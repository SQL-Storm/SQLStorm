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
    u.Reputation,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.CreationDate AS DATE)
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_day,
    SUM(p.ViewCount) OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_views
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
extended AS (
  SELECT
    rq.*,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = rq.PostId AND a.PostTypeId = 2) AS answer_count,
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
  (COALESCE(e.answer_count, 0) + COALESCE(e.comment_count_q, 0)) * 1.0 / (e.ViewCount + 1) AS engagement_density,
  (LENGTH(e.Title) * 1.0 / NULLIF(LENGTH(REPLACE(e.Title, ' ', '')), 0)) AS title_word_density,
  MD5(e.Tags) AS tags_hash,
  CASE
    WHEN e.Reputation IS NULL THEN 'unknown'
    WHEN e.Reputation > 10000 AND e.Score > 50 THEN 'stellar'
    WHEN e.Reputation > 1000 AND e.Score > 20 THEN 'strong'
    ELSE 'regular'
  END AS categorization
FROM extended e
JOIN PostLinks pl ON pl.PostId = e.PostId
LEFT JOIN Votes v ON v.PostId = e.PostId
WHERE EXISTS (
    SELECT 1
    FROM PostHistory ph
    WHERE ph.PostId = e.PostId
      AND ph.PostHistoryTypeId IN (16, 50)
)
GROUP BY
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
  e.answer_count,
  e.comment_count_q
ORDER BY
  e.rolling_7d_views DESC,
  e.Score DESC,
  e.LastActivityDate DESC
LIMIT 100;