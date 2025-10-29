-- {"query": "5396.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 733} 
WITH Trending AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    COUNT(DISTINCT v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts
  FROM
    Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE
    p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
  GROUP BY
    p.Id, p.Title, p.Tags, p.PostTypeId, p.CreationDate, p.LastActivityDate, p.OwnerUserId, p.ViewCount, p.Score
),
Aggregated AS (
  SELECT
    t.PostId,
    t.Title,
    t.Tags,
    t.PostTypeId,
    t.CreationDate,
    t.LastActivityDate,
    t.OwnerUserId,
    t.ViewCount,
    t.Score,
    t.VoteCount,
    t.UpVotes,
    t.DownVotes,
    t.BountyStarts,
    u.Reputation,
    u.DisplayName AS OwnerName,
    array_length(string_to_array(t.Tags, '><'), 1) AS TagCount,
    CASE
      WHEN t.PostTypeId = 1 THEN 1
      ELSE 0
    END AS IsQuestion
  FROM
    Trending t
    LEFT JOIN Users u ON u.Id = t.OwnerUserId
),
Windowed AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (
      PARTITION BY IsQuestion
      ORDER BY
        (Score * 2 + VoteCount * 3 + UpVotes - DownVotes) DESC,
        LastActivityDate DESC
    ) AS rn,
    AVG(ViewCount) OVER (
      PARTITION BY IsQuestion
    ) AS AvgViewsByType
  FROM Aggregated a
)
SELECT
  w.PostId,
  w.Title,
  w.Tags,
  w.PostTypeId,
  w.CreationDate,
  w.LastActivityDate,
  w.OwnerUserId,
  w.OwnerName,
  w.Reputation,
  w.ViewCount,
  w.Score,
  w.VoteCount,
  w.UpVotes,
  w.DownVotes,
  w.BountyStarts,
  w.TagCount,
  w.IsQuestion,
  w.rn,
  w.AvgViewsByType,
  CASE
    WHEN w.TagCount IS NULL THEN 0
    ELSE w.TagCount
  END AS TagCountSafe,
  -- Elaborate computed field with NULL-safe arithmetic
  (COALESCE(w.ViewCount,0) * 2 + COALESCE(w.UpVotes,0) - COALESCE(w.DownVotes,0)
   + COALESCE(w.BountyStarts,0)) AS EngagementScore
FROM Windowed w
WHERE w.rn = 1
  AND (w.Reputation > 1000 OR w.Score > 5)
ORDER BY EngagementScore DESC
LIMIT 50
OFFSET 0
;