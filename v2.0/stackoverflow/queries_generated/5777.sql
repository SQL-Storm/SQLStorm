-- {"query": "5777.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 741} 
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    -- computed popularity score with NULL-safe arithmetic
    COALESCE(p.Score,0) * 2 + COALESCE(p.ViewCount,0) * 0.5 + COALESCE(p.AnswerCount,0) * 3 +
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.BountyAmount IS NOT NULL) AS PopularityScore
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate > NOW() - INTERVAL '180 days'
),
TagSpark AS (
  SELECT
    rt.PostId,
    rt.Title,
    unnest(string_to_array(substr(rt.Tags, 2, length(rt.Tags)-2), '><')) AS Tag,
    rt.PopularityScore
  FROM RecentActivity rt
  WHERE rt.PostTypeId = 1
),
TagStats AS (
  SELECT
    ts.Tag,
    COUNT(*) AS PostCount,
    AVG(ts.PopularityScore) AS AvgPopularity
  FROM TagSpark ts
  GROUP BY ts.Tag
),
TopTags AS (
  SELECT
    ts.Tag,
    ts.PostCount,
    ts.AvgPopularity
  FROM TagStats ts
  ORDER BY ts.AvgPopularity DESC NULLS LAST, ts.PostCount DESC
  LIMIT 20
),
CorrelatedPosts AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.OwnerUserId,
    tp.ViewCount,
    tp.Score,
    tp.CommentCount,
    tp.AnswerCount,
    tp.Tags,
    tp.LastActivityDate,
    t.Name AS TagName
  FROM TopTags tt
  JOIN TagSpark tp ON tp.Tag = tt.Tag
  LEFT JOIN Tags t ON t.TagName = tt.Tag
),
Combined AS (
  SELECT
    cp.PostId,
    cp.Title,
    cp.OwnerUserId,
    cp.ViewCount,
    cp.Score,
    cp.CommentCount,
    cp.AnswerCount,
    cp.LastActivityDate,
    cp.TagName,
    ROW_NUMBER() OVER (PARTITION BY cp.OwnerUserId ORDER BY cp.LastActivityDate DESC) AS rn
  FROM CorrelatedPosts cp
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerUserId,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.AnswerCount,
  c.LastActivityDate,
  c.TagName,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.AccountId,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = c.OwnerUserId) AS PostsByOwner,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = c.PostId AND v.BountyAmount IS NOT NULL) AS AvgBounty
FROM Combined c
JOIN Users u ON c.OwnerUserId = u.Id
WHERE c.rn = 1
ORDER BY c.LastActivityDate DESC
LIMIT 100
;