-- {"query": "5658.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 855}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TaggedQuestions AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
PopularTags AS (
  SELECT
    t.Tag,
    COUNT(*) AS PostCount,
    MAX(p.ViewCount) AS MaxViews,
    AVG(p.Score) AS AvgScore
  FROM TaggedQuestions t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.Tag
  HAVING COUNT(*) > 5
),
CorrelatedHistory AS (
  SELECT
    p.Id AS PostId,
    ph.Id AS HistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId AS EditorUserId,
    ph.Comment
  FROM Posts p
  LEFT JOIN PostHistory ph
    ON ph.PostId = p.Id
  WHERE ph.PostHistoryTypeId IN (4,5,6,10,16)
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14 days'
),
Summary AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    ARRAY_AGG(DISTINCT rp.Tags) FILTER (WHERE rp.Tags IS NOT NULL) AS TagsList,
    COALESCE(SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesLast14d,
    COALESCE(SUM(CASE WHEN rv.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesLast14d,
    COALESCE(SUM(CASE WHEN rv.VoteTypeId = 8 THEN 1 ELSE 0 END), 0) AS BountyStartsLast14d
  FROM RecentActivePosts rp
  LEFT JOIN RecentVotes rv ON rv.PostId = rp.Id
  -- original attempted join to Tags table used t.Tag which didn't exist; aggregate the Posts.Tags string instead
  GROUP BY rp.Id, rp.Title, rp.OwnerUserId, rp.CreationDate, rp.LastActivityDate, rp.ViewCount, rp.Score, rp.Tags
)
SELECT
  s.PostId,
  s.Title,
  u.DisplayName AS Owner,
  s.CreationDate,
  s.LastActivityDate,
  s.ViewCount,
  s.Score,
  s.TagsList,
  s.UpVotesLast14d,
  s.DownVotesLast14d,
  s.BountyStartsLast14d,
  pc.PostCount AS RelatedPostCount,
  pc.MaxViews AS RelatedMaxViews,
  pc.AvgScore AS RelatedAvgScore,
  rt.Tag AS MostEngagedTag
FROM Summary s
LEFT JOIN Users u ON u.Id = s.OwnerUserId
LEFT JOIN (
  SELECT
    p.Id,
    COUNT(pl.Id) AS PostCount,
    MAX(p.ViewCount) AS MaxViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
) pc ON pc.Id = s.PostId
LEFT JOIN (
  SELECT Tag, COUNT(*) AS cnt
  FROM TaggedQuestions
  GROUP BY Tag
  ORDER BY cnt DESC
  LIMIT 1
) rt ON TRUE
ORDER BY s.LastActivityDate DESC
LIMIT 100;