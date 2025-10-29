-- {"query": "5111.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 788} 
WITH RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p_ViewCount := p.ViewCount,
    p_Score := p.Score,
    -- windowed aggregates for activity context
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId IN (2,3)) OVER (PARTITION BY p.Id) AS NetVotes,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) OVER (PARTITION BY p.Id) AS LastUpvoteDate,
    MAX(CASE WHEN v.VoteTypeId = 3 THEN v.CreationDate END) OVER (PARTITION BY p.Id) AS LastDownvoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2) -- questions and answers for benchmarking
),
TaggedDerived AS (
  SELECT
    ra.*,
    t.TagName,
    ROW_NUMBER() OVER (PARTITION BY ra.PostId ORDER BY ra.CreationDate DESC) AS rn
  FROM RecentActivity ra
  LEFT JOIN unnest(string_to_array(
    substring(ra.Tags, 2, length(ra.Tags)-2), '><') ) WITH ORDINALITY AS t(TagName, ord)
    ON TRUE
  WHERE ra.PostTypeId = 1
),
CorrelatedPerf AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    u.Id AS OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    p.Score,
    p.ViewCount,
    p.Tags,
    COALESCE(vt.Name, 'Unknown') AS VoteTypeName,
    v.BountyAmount,
    CASE
      WHEN p.OwnerUserId IS NOT NULL THEN
        (SELECT AVG(Length(Body)) FROM Posts WHERE Id = p.Id)
      ELSE NULL
    END AS ApproxBodyLength
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE p.Id IN (SELECT PostId FROM RecentActivity)
)
SELECT
  cp.PostId,
  cp.Title,
  cp.CreationDate,
  cp.LastActivityDate,
  cp.OwnerUserId,
  cp.OwnerDisplayName,
  cp.Reputation,
  cp.Score,
  cp.ViewCount,
  cp.Tags,
  string_agg(DISTINCT t.TagName, ',') AS TagList,
  MAX(cp.ApproxBodyLength) OVER () AS GlobalAvgBodyLength,
  SUM(CASE WHEN cp.Score > 0 THEN 1 ELSE 0 END) OVER () AS PositiveScorePosts,
  SUM(CASE WHEN cp.Score < 0 THEN 1 ELSE 0 END) OVER () AS NegativeScorePosts,
  COUNT(cp.PostId) OVER () AS TotalPostsConsidered,
  MIN(cp.CreationDate) OVER () AS EarliestPostDate,
  MAX(cp.LastActivityDate) OVER () AS LatestActivityDate,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = cp.OwnerUserId) AS PostsByOwner
FROM CorrelatedPerf cp
LEFT JOIN TagDerived td ON td.PostId = cp.PostId
GROUP BY
  cp.PostId, cp.Title, cp.CreationDate, cp.LastActivityDate,
  cp.OwnerUserId, cp.OwnerDisplayName, cp.Reputation,
  cp.Score, cp.ViewCount, cp.Tags;