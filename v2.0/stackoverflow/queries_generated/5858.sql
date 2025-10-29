-- {"query": "5858.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 730} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    u.Id AS OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpModCount,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate > NOW() - INTERVAL '365 days'
),
PopularTags AS (
  SELECT
    tg.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM UNNEST(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '><')) AS tg(TagName)
  JOIN Posts p ON p.Id = p.Id
  JOIN Tags t ON t.TagName = tg.TagName
  GROUP BY tg.TagName
  HAVING COUNT(*) > 5
),
Flagged AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.LastActivityDate,
    p.Score,
    v.VoteTypeId,
    v.UserId AS VoterUserId,
    v.CreationDate AS VoteDate,
    u.DisplayName AS VoterDisplayName
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE v.VoteTypeId = 16 -- ModeratorReview
    AND p.LastActivityDate > NOW() - INTERVAL '180 days'
),
Combo AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.LastActivityDate,
    rh.Score,
    rh.ViewCount,
    rh.OwnerUserId,
    rh.OwnerDisplayName,
    rh.UpVotes,
    rh.DownVotes,
    pt.Name AS PostType,
    COALESCE(p.Title, rh.Title) AS EffectiveTitle
  FROM RecentHot rh
  LEFT JOIN PostTypes pt ON pt.Id = 1
  WHERE rh.rn <= 100
)
SELECT
  c.PostId,
  c.EffectiveTitle AS Title,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.UpVotes,
  c.DownVotes,
  c.PostType
FROM Combo c
LEFT JOIN PostTypes pt ON pt.Id = 1
UNION ALL
SELECT
  f.PostId,
  f.Title,
  f.LastActivityDate,
  f.Score,
  NULL AS ViewCount,
  NULL AS OwnerUserId,
  NULL AS OwnerDisplayName,
  NULL AS UpVotes,
  NULL AS DownVotes,
  NULL AS PostType
FROM Flagged f
ORDER BY LastActivityDate DESC, Score DESC
LIMIT 500;