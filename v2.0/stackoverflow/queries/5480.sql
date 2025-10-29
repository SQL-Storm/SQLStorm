-- {"query": "5480.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1020} 
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_owner
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
OwnerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(*) AS PostsInLast6m,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositivePosts,
    SUM(CASE WHEN p.Score < 0 THEN 1 ELSE 0 END) AS NegativePosts,
    MAX(p.LastActivityDate) AS LastActivePostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.Reputation >= 100
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagEngagement AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    SUM(CASE WHEN pv.PostId IS NOT NULL THEN 1 ELSE 0 END) AS LinkedPosts
  FROM Tags t
  LEFT JOIN (
    SELECT DISTINCT p.Id AS PostId, unnest(string_to_array(p.Tags, '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) pv ON pv.TagName = t.TagName
  GROUP BY t.TagName
),
PopularPosts AS (
  SELECT
    r.PostId,
    r.Title,
    r.LastActivityDate,
    r.OwnerUserId,
    r.Score,
    r.ViewCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 3) AS DownVotes,
    CASE
      WHEN r.Score > 0 THEN 'Positive'
      WHEN r.Score = 0 THEN 'Neutral'
      ELSE 'Negative'
    END AS Sentiment
  FROM RecentActivity r
  WHERE r.rn_by_owner = 1
    AND r.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
ComplexMeasure AS (
  SELECT
    pp.PostId,
    pp.Title,
    pp.LastActivityDate,
    pp.OwnerUserId,
    pp.ViewCount,
    pp.Score,
    pp.UpVotes,
    pp.DownVotes,
    (pp.UpVotes - pp.DownVotes) AS NetVotes,
    (pp.ViewCount * 0.3 + GREATEST(pp.UpVotes, 1) * 2) AS EngagementScore
  FROM PopularPosts pp
),
CrossSource AS (
  SELECT
    cr.PostId,
    cr.Title,
    cr.LastActivityDate,
    cr.OwnerUserId,
    cr.EngagementScore,
    coalesce(ou.Reputation, 0) AS OwnerReputation
  FROM ComplexMeasure cr
  LEFT JOIN Users ou ON ou.Id = cr.OwnerUserId
),
FinalOutput AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.LastActivityDate,
    cs.OwnerUserId,
    cs.EngagementScore,
    cs.OwnerReputation,
    CASE
      WHEN cs.EngagementScore > 100 THEN 'Elite'
      WHEN cs.EngagementScore > 50 THEN 'Strong'
      WHEN cs.EngagementScore > 0 THEN 'Moderate'
      ELSE 'Low'
    END AS Tier,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputationFromTable
  FROM CrossSource cs
  LEFT JOIN Users ua ON ua.Id = cs.OwnerUserId
  ORDER BY cs.EngagementScore DESC NULLS LAST
  LIMIT 100
)
SELECT
  fo.PostId,
  fo.Title,
  fo.LastActivityDate,
  fo.OwnerUserId,
  fo.EngagementScore,
  fo.OwnerReputation,
  fo.Tier,
  fo.OwnerDisplayName,
  fo.OwnerReputationFromTable
FROM FinalOutput fo
JOIN PostLinks pl ON pl.PostId = fo.PostId AND pl.LinkTypeId = 1
LEFT JOIN Comments c ON c.PostId = fo.PostId
LEFT JOIN Votes v ON v.PostId = fo.PostId AND v.VoteTypeId = 2
LEFT JOIN PostHistory ph ON ph.PostId = fo.PostId AND ph.PostHistoryTypeId = 10
WHERE fo.EngagementScore IS NOT NULL
  AND fo.OwnerUserId IS NOT NULL
  AND fo.LastActivityDate IS NOT NULL
;