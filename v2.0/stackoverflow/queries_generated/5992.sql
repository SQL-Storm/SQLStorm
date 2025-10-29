-- {"query": "5992.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 719} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.FavoriteCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
doorway AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.PostTypeId,
    -- derived metrics
    (rp.Score * 1.0 / NULLIF(rp.ViewCount,0)) AS score_per_view,
    CASE
      WHEN rp.OwnerUserId IS NULL THEN 'Unknown'
      ELSE CAST(u.Reputation AS varchar)
    END AS owner_reputation,
    COUNT(*) OVER () AS total_similar_posts
  FROM ranked_posts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = rp.PostId
  LEFT JOIN Posts pp ON pp.Id = pl.RelatedPostId
  WHERE rp.rn_by_type = 1
),
complex_calc AS (
  SELECT
    d.PostId,
    d.Title,
    d.CreationDate,
    d.Score,
    d.ViewCount,
    d.OwnerUserId,
    d.LastActivityDate,
    d.PostTypeId,
    d.score_per_view,
    d.owner_reputation,
    -- correlated subquery: count of comments on the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = d.PostId) AS CommentCountOnPost,
    -- window function over posts by day
    SUM(d.Score) OVER (PARTITION BY DATE(d.CreationDate)) AS TotalScoreInDay
  FROM doorway d
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.CommentCountOnPost,
  c.TotalScoreInDay,
  c.owner_reputation,
  CASE
    WHEN c.Score > 0 AND c.CommentCountOnPost > 10 THEN 'Active positively'
    WHEN c.Score <= 0 AND c.CommentCountOnPost > 5 THEN 'Negatively active'
    ELSE 'Steady'
  END AS ActivityLabel,
  -- advanced expression: a nested conditional with NULL handling
  CASE
    WHEN c.OwnerUserId IS NULL THEN NULL
    WHEN EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = c.OwnerUserId
        AND b.Class = 1
        AND b.Date > c.CreationDate - INTERVAL '30 days'
    ) THEN 'GoldBadgeRecent'
    ELSE 'NoRecentGoldBadge'
  END AS GoldBadgeStatus
FROM complex_calc c
ORDER BY c.TotalScoreInDay DESC, c.Score DESC
LIMIT 100;