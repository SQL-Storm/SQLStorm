-- {"query": "5204.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 640} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(b.Class, 0) AS BadgeClass,
    COUNT(CASE WHEN v2.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY p.Id) AS UpvotesFromVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v2 ON v2.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2)
),
complex_derived AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.Reputation,
    rp.OwnerDisplayName,
    rp.BadgeClass,
    rp.UpvotesFromVotes,
    CASE
      WHEN rp.ViewCount > 1000 THEN 'high-traffic'
      WHEN rp.ViewCount BETWEEN 100 AND 999 THEN 'medium-traffic'
      ELSE 'low-traffic'
    END AS TrafficBand,
    AVG(pv.BountyAmount) OVER (PARTITION BY rp.Id) AS AvgBounty,
    (SELECT AVG(kt.Count) FROM Tags kt WHERE kt.IsModeratorOnly = 0) AS GlobalTagDensity
  FROM ranked_posts rp
  LEFT JOIN Votes pv ON pv.PostId = rp.Id AND pv.VoteTypeId = 8
),
window_enhanced AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (PARTITION BY c.OwnerUserId ORDER BY c.CreationDate DESC) AS rn_by_owner,
    SUM(CASE WHEN c.TrafficBand = 'high-traffic' THEN 1 ELSE 0 END) OVER () AS HighTrafficCount
  FROM complex_derived c
),
filters AS (
  SELECT *
  FROM window_enhanced
  WHERE rn_by_owner = 1
    AND AvgBounty IS NOT NULL
    AND HighTrafficCount > 0
)
SELECT
  f.Id,
  f.Title,
  f.CreationDate,
  f.OwnerDisplayName,
  f.Reputation AS OwnerReputation,
  f.Score,
  f.ViewCount,
  f.Tags,
  f.AnswerCount,
  f.CommentCount,
  f.LastActivityDate,
  f.TrafficBand,
  f.AvgBounty,
  f.GlobalTagDensity,
  f.BadgeClass
FROM filters f
ORDER BY f.TrafficBand DESC, f.Score DESC, f.ViewCount DESC
LIMIT 100;