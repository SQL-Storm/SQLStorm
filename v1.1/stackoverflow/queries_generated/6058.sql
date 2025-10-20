-- {"query": "6058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 741} 
WITH RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Votes v
    ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.OwnerDisplayName, p.LastActivityDate
),
TagWeight AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
Agg AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.Tags,
    rh.CreationDate,
    rh.Score,
    rh.ViewCount,
    rh.OwnerUserId,
    rh.OwnerDisplayName,
    rh.LastActivityDate,
    COUNT(*) FILTER (WHERE tv.VoteTypeId = 2) AS UpVotesSinceCreation,
    COUNT(*) FILTER (WHERE tv.VoteTypeId = 3) AS DownVotesSinceCreation,
    MAX(tv.CreationDate) AS LastVoteDate
  FROM RecentHot rh
  LEFT JOIN Votes tv
    ON tv.PostId = rh.PostId
  GROUP BY
    rh.PostId, rh.Title, rh.Tags, rh.CreationDate, rh.Score, rh.ViewCount, rh.OwnerUserId, rh.OwnerDisplayName, rh.LastActivityDate
),
Timeline AS (
  SELECT
    a.PostId,
    a.Title,
    a.OwnerUserId,
    a.OwnerDisplayName,
    a.CreationDate,
    a.LastActivityDate,
    a.UpVotesSinceCreation,
    a.DownVotesSinceCreation,
    ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.LastVoteDate DESC NULLS LAST) AS rn
  FROM Agg a
  LEFT JOIN RecentHot rh2 ON rh2.PostId = a.PostId
  LEFT JOIN Votes v ON v.PostId = a.PostId
  GROUP BY
    a.PostId, a.Title, a.OwnerUserId, a.OwnerDisplayName, a.CreationDate, a.LastActivityDate, a.UpVotesSinceCreation, a.DownVotesSinceCreation, a.LastVoteDate
)
SELECT
  t1.OwnerUserId,
  t1.OwnerDisplayName,
  COUNT(*) AS PostsInTopTier,
  AVG(EXTRACT(EPOCH FROM (COALESCE(t1.LastActivityDate, t1.CreationDate) - t1.CreationDate)) / 3600) AS AvgHoursActive,
  SUM(CASE WHEN t1.UpVotesSinceCreation > t1.DownVotesSinceCreation THEN 1 ELSE 0 END) AS NetPositiveVotesPosts,
  STRING_AGG(t1.Title, ' | ') AS TitlesSummary,
  MIN(t1.CreationDate) AS FirstPostDate,
  MAX(t1.LastActivityDate) AS LastActivityAcrossPosts
FROM Timeline t1
GROUP BY t1.OwnerUserId, t1.OwnerDisplayName
HAVING COUNT(*) > 5
ORDER BY PostsInTopTier DESC, AvgHoursActive DESC
LIMIT 100;