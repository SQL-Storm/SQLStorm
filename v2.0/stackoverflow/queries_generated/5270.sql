-- {"query": "5270.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 805} 
WITH TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    p.Id AS PostId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
  FROM Posts p
  JOIN Tags t ON t.ExcerptPostId = p.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
TagAggregates AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    AVG(p.ViewCount) AS AvgViews,
    MAX(p.CreationDate) AS LastCreated
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  WHERE t.rn = 1
  GROUP BY t.TagName
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    v.VoteCount AS UpDownDelta
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS VoteCount
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND ph.PostHistoryTypeId IN (50,52,53) -- CommunityBump / Hot question status changes (example)
),
Combined AS (
  SELECT
    t.TagName,
    ta.PostCount,
    ta.AvgScore,
    ta.AvgViews,
    ta.LastCreated,
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score AS PostScore,
    ra.ViewCount AS PostViews,
    ra.UpDownDelta
  FROM TagAggregates ta
  LEFT JOIN RecentActivity ra ON 1 = 1
  CROSS JOIN (
    SELECT DISTINCT TagName FROM TagAggregates
  ) AS d
  WHERE ta.TagName = d.TagName
)
SELECT
  t.TagName,
  ta.PostCount,
  ta.AvgScore,
  ta.AvgViews,
  ta.LastCreated,
  ra.PostId,
  ra.Title,
  ra.OwnerUserId,
  wo.DisplayName AS OwnerDisplayName,
  ra.CreationDate,
  ra.LastActivityDate,
  ra.PostScore,
  ra.PostViews,
  ra.UpDownDelta
FROM TagAggregates ta
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViews,
    COALESCE(v.SumUpDown, 0) AS UpDownDelta
  FROM Posts p
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 WHEN VoteTypeId = 3 THEN -1 ELSE 0 END) AS SumUpDown
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
) ra ON ra.PostId IN (
  SELECT Id FROM Posts WHERE Id = ra.PostId
)
LEFT JOIN Users wo ON wo.Id = ra.OwnerUserId
ORDER BY ta.TagName, ra.LastActivityDate DESC
LIMIT 100;