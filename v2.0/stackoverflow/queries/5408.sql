-- {"query": "5408.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1033}
WITH recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
tag_hotness AS (
  SELECT
    x.TagName,
    COUNT(x.Id) AS PostCount,
    AVG(x.Score) AS AvgScore,
    SUM(x.ViewCount) AS TotalViews,
    MAX(x.LastActivityDate) AS LastActive
  FROM (
    SELECT
      CAST(unnested AS text) AS TagName,
      rp.PostId AS Id,
      rp.Score,
      rp.ViewCount,
      rp.LastActivityDate
    FROM recent_posts rp
    CROSS JOIN LATERAL unnest(string_to_array(rp.Tags, '>')) AS unnested
    WHERE rp.Tags IS NOT NULL
  ) AS x
  GROUP BY x.TagName
  ORDER BY PostCount DESC
  LIMIT 50
),
cross_ref AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    u.Reputation,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    v.BountyAmount,
    CASE
      WHEN u.Reputation >= 10000 THEN 'high'
      WHEN u.Reputation >= 1000 THEN 'medium'
      ELSE 'low'
    END AS RepBand,
    CASE
      WHEN rp.ParentId IS NULL THEN 'root'
      ELSE 'child'
    END AS PostKind
  FROM recent_posts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  WHERE v.VoteTypeId IN (2, 3, 12, 16)
),
complex_calc AS (
  SELECT
    cr.PostId,
    cr.Title,
    cr.OwnerUserId,
    cr.Reputation,
    cr.VoteTypeId,
    cr.VoteDate,
    cr.BountyAmount,
    cr.RepBand,
    cr.PostKind,
    (EXTRACT(EPOCH FROM (cr.VoteDate - rp.CreationDate)) / 3600.0) AS HoursBetweenPostAndVote,
    (CASE WHEN cr.BountyAmount IS NULL THEN 0 ELSE cr.BountyAmount END) AS BountyIfAny,
    (CASE WHEN cr.RepBand = 'high' THEN 1 ELSE 0 END) AS IsPromoted,
    rp.CreationDate
  FROM cross_ref cr
  LEFT JOIN Posts rp ON cr.PostId = rp.Id
),
windowed AS (
  SELECT
    pc.PostId,
    pc.Title,
    pc.OwnerUserId,
    pc.Reputation,
    pc.VoteTypeId,
    pc.VoteDate,
    pc.BountyAmount,
    pc.RepBand,
    pc.PostKind,
    pc.HoursBetweenPostAndVote,
    pc.BountyIfAny,
    pc.IsPromoted,
    SUM(pc.IsPromoted) OVER (PARTITION BY pc.PostKind ORDER BY pc.VoteDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningPromotions,
    ROW_NUMBER() OVER (PARTITION BY pc.PostKind ORDER BY pc.HoursBetweenPostAndVote DESC) AS ReverseChron
  FROM complex_calc pc
),
final AS (
  SELECT
    w.PostId,
    w.Title,
    w.OwnerUserId,
    w.Reputation,
    w.VoteTypeId,
    w.VoteDate,
    w.BountyAmount,
    w.RepBand,
    w.PostKind,
    w.HoursBetweenPostAndVote,
    w.BountyIfAny,
    w.IsPromoted,
    w.RunningPromotions,
    w.ReverseChron,
    CASE
      WHEN w.RepBand = 'high' AND w.IsPromoted = 1 THEN 'hot_promoter'
      WHEN w.RepBand = 'medium' AND w.HoursBetweenPostAndVote < 24 THEN 'hot_recent'
      ELSE 'normal'
    END AS Category
  FROM windowed w
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerUserId,
  f.Reputation,
  f.VoteTypeId,
  f.VoteDate,
  f.BountyAmount,
  f.RepBand,
  f.PostKind,
  f.HoursBetweenPostAndVote,
  f.BountyIfAny,
  f.IsPromoted,
  f.RunningPromotions,
  f.ReverseChron,
  f.Category,
  t.ActivityTier AS TagCategory
FROM final f
LEFT JOIN (
  SELECT
    TagName,
    CASE
      WHEN PostCount >= 20 THEN 'high_activity'
      WHEN PostCount >= 5 THEN 'medium_activity'
      ELSE 'low_activity'
    END AS ActivityTier
  FROM tag_hotness
) t ON true
ORDER BY f.Category, f.RunningPromotions DESC, f.HoursBetweenPostAndVote ASC
LIMIT 200;