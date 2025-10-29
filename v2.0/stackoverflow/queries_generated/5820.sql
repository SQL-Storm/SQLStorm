-- {"query": "5820.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 746} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
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
    p.Body,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn_by_type
  FROM Posts p
  WHERE p.ClosedDate IS NULL
    AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
recent_activity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    vt.Name AS VoteTypeName,
    v.BountyAmount,
    pb.IsGold := CASE WHEN b.Class = 1 THEN 1 ELSE 0 END
  FROM ranked_posts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = rp.PostId
  LEFT JOIN Tags t ON t.Id = rp.ParentId
  WHERE rp.rn_by_type = 1
),
cte_enriched AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.CommentCount,
    ra.AnswerCount,
    ra.Reputation,
    ra.DisplayName,
    ra.Location,
    ra.AccountId,
    ra.VoteTypeName,
    ra.BountyAmount,
    CASE
      WHEN ra.Location IS NULL THEN 'Unknown'
      ELSE ra.Location
    END AS LocationNormalized,
    CONCAT_WS(' | ', ra.Title, COALESCE(NULLIF(ra.VoteTypeName, ''), 'NoVote')) AS TitleWithMeta,
    -- complex numeric expression including NULL-safe arithmetic
    COALESCE(ra.Score, 0) * 1.0 / NULLIF(COALESCE(ra.ViewCount, 0) + 1, 0) AS ScorePerView
  FROM recent_activity ra
)
SELECT
  c.PostId,
  c.TitleWithMeta AS DisplayTitle,
  c.OwnerUserId,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.AnswerCount,
  c.Reputation,
  c.DisplayName,
  c.LocationNormalized,
  c.AccountId,
  c.VoteTypeName,
  c.BountyAmount,
  c.LocationNormalized,
  c.ScorePerView
FROM cte_enriched c
WHERE c.Score IS NOT NULL
  AND c.ViewCount >= 0
  AND c.Reputation >= 0
  AND EXISTS (
    SELECT 1
    FROM PostLinks pl
    WHERE pl.PostId = c.PostId
      AND pl.RelatedPostId IS NOT NULL
  )
ORDER BY c.Score DESC NULLS LAST, c.LastActivityDate DESC
LIMIT 100;