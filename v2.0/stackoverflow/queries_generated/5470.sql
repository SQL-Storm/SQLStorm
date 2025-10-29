-- {"query": "5470.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 903} 
WITH recent_active AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.ViewCount,
    p.Score,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.LastActivityDate >= CURRENT_DATE - INTERVAL '90 days'
),
tag_metrics AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS question_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
           p.*
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) AS q
  JOIN Tags t ON t.TagName = q.TagName
  GROUP BY t.TagName
),
cross_joined AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerUserId,
    ra.PostTypeId,
    ra.ViewCount,
    ra.Score,
    ra.Tags,
    u.Reputation,
    u.DisplayName,
    b.Class AS BadgeClass,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    v.BountyAmount
  FROM recent_active ra
  LEFT JOIN Users u ON ra.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.PostId = ra.PostId
  WHERE ra.rn_owner = 1
),
complex AS (
  SELECT
    c.PostId,
    c.Title,
    c.CreationDate,
    c.LastActivityDate,
    c.OwnerUserId,
    c.PostTypeId,
    c.ViewCount,
    c.Score,
    c.Tags,
    c.Reputation,
    c.DisplayName,
    c.BadgeClass,
    c.VoteTypeId,
    c.VoteDate,
    c.BountyAmount,
    CASE
      WHEN c.PostTypeId = 1 THEN 'Question'
      WHEN c.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    CASE
      WHEN c.ViewCount > 1000 THEN 'Popular'
      WHEN c.Score > 10 THEN 'Hot'
      ELSE 'Regular'
    END AS ActivityLabel
  FROM cross_joined c
  WHERE c.VoteTypeId IN (2,7) -- UpMod or Reopen as performance-insight anchors
     OR c.BountyAmount IS NOT NULL
     OR c.ViewCount > 500
),
further AS (
  SELECT
    p.PostId,
    p.Title,
    p.PostKind,
    p.ActivityLabel,
    p.Reputation,
    p.DisplayName,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.VoteDate,
    p.BountyAmount
  FROM complex p
  JOIN LATERAL (
    SELECT 1
  ) AS t ON true
),
final AS (
  SELECT
    f.PostId,
    f.Title,
    f.PostKind,
    f.ActivityLabel,
    f.Reputation,
    f.DisplayName,
    f.ViewCount,
    f.Score,
    f.Tags,
    f.VoteDate,
    f.BountyAmount,
    (CASE WHEN f.Reputation IS NULL THEN 0 ELSE f.Reputation END) +
    (CASE WHEN f.ViewCount IS NULL THEN 0 ELSE f.ViewCount END) AS PowerScore,
    ROW_NUMBER() OVER (PARTITION BY f.PostKind ORDER BY f.PowerScore DESC) AS rn
  FROM further f
)
SELECT
  PostId,
  Title,
  PostKind,
  ActivityLabel,
  Reputation,
  DisplayName,
  ViewCount,
  Score,
  Tags,
  VoteDate,
  BountyAmount,
  PowerScore
FROM final
WHERE rn <= 100
ORDER BY PostKind, PowerScore DESC
;