-- {"query": "57.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1053} 
WITH flagged_post_counts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.ContentLicense,
    p.Body,
    COALESCE(vt_total.cnt, 0) AS TotalVotes,
    COALESCE(bs.latent_bounties, 0) AS ActiveBounties
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS cnt
    FROM Votes
    WHERE VoteTypeId IN (2,3) -- UpMod, DownMod
    GROUP BY PostId
  ) vt_total ON vt_total.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, SUM(COALESCE(BountyAmount,0)) AS latent_bounties
    FROM Votes v
    WHERE v.VoteTypeId = 8 -- BountyStart
    GROUP BY PostId
  ) bs ON bs.PostId = p.Id
  WHERE p.PostTypeId IN (1,2) -- include Questions and Answers for benchmarking
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.Body,
    p.ContentLicense,
    ARRAY_AGG(CASE WHEN c.PostId IS NOT NULL THEN c.Id END) FILTER (WHERE c.Id IS NOT NULL) AS CommentIds
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.Title, p.Tags, p.Body, p.ContentLicense
),
complex_candidates AS (
  SELECT
    r.PostId,
    r.OwnerUserId,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.Title,
    r.Tags,
    r.Body,
    r.ContentLicense,
    f.TotalVotes,
    f.ActiveBounties,
    ROW_NUMBER() OVER (
      PARTITION BY r.OwnerUserId
      ORDER BY r.Score DESC, r.LastActivityDate DESC, r.ViewCount DESC
    ) AS rn_by_owner
  FROM recent_activity r
  LEFT JOIN flagged_post_counts f ON f.PostId = r.PostId
  WHERE r.LastActivityDate > (CURRENT_DATE - INTERVAL '180 days')
    AND (r.Score > 0 OR f.TotalVotes > 5 OR f.ActiveBounties > 0)
),
cte_window AS (
  SELECT
    *,
    LAG(LastActivityDate) OVER (PARTITION BY OwnerUserId ORDER BY LastActivityDate) AS PrevActivityDate,
    LEAD(LastActivityDate) OVER (PARTITION BY OwnerUserId ORDER BY LastActivityDate) AS NextActivityDate
  FROM complex_candidates
  WHERE rn_by_owner = 1
),
advanced_filter AS (
  SELECT
    c.PostId,
    c.OwnerUserId,
    c.Title,
    c.Tags,
    c.Body,
    c.CreationDate,
    c.LastActivityDate,
    c.TotalVotes,
    c.ActiveBounties,
    CASE
      WHEN c.TotalVotes > 20 THEN 'high_votes'
      WHEN c.ActiveBounties > 0 THEN 'bounty'
      WHEN EXTRACT(HOUR FROM (c.LastActivityDate - c.CreationDate)) < 24 THEN 'rapid'
      ELSE 'other'
    END AS design_group
  FROM cte_window c
  WHERE c.rn_by_owner = 1
    AND (EXTRACT(EPOCH FROM (c.LastActivityDate - c.CreationDate)) / 3600) > 1
)
SELECT
  af.design_group,
  af.PostId,
  af.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  af.Title,
  af.Tags,
  af.Body,
  af.CreationDate,
  af.LastActivityDate,
  af.TotalVotes,
  af.ActiveBounties,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.Location,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = af.PostId AND v.BountyAmount IS NOT NULL) AS AvgBountyAmount,
  (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = af.PostId) AS CommentCount
FROM advanced_filter af
JOIN Users u ON u.Id = af.OwnerUserId
ORDER BY
  CASE af.design_group
    WHEN 'high_votes' THEN 1
    WHEN 'bounty' THEN 2
    WHEN 'rapid' THEN 3
    ELSE 4
  END,
  af.LastActivityDate DESC
LIMIT 100;