-- {"query": "5771.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 784} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate IS NOT NULL
),
TopTags AS (
  SELECT
    UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tagname,
    p.Id AS PostId
  FROM RecentHot p
),
TagStats AS (
  SELECT
    t.tagname,
    COUNT(*) AS question_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.tagname
),
CorrelatedStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    b.Class AS BadgeClass
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.Reputation > 1000
),
ComplexFilters AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    CASE
      WHEN p.Score > 50 THEN 'high'
      WHEN p.Score > 20 THEN 'mid'
      ELSE 'low'
    END AS ScoreBand,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBounty,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS VoteCountScenario
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > p.CreationDate
    AND p.ViewCount IS NOT NULL
),
Joined AS (
  SELECT
    c.PostId,
    c.Title,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.LastActivityDate,
    c.ScoreBand,
    c.AvgBounty,
    c.VoteCountScenario,
    t.tagname
  FROM ComplexFilters c
  LEFT JOIN TopTags t ON t.PostId = c.PostId
),
Final AS (
  SELECT
    j.PostId,
    j.Title,
    j.Score,
    j.ViewCount,
    j.CreationDate,
    j.LastActivityDate,
    j.ScoreBand,
    j.AvgBounty,
    j.VoteCountScenario,
    j.tagname,
    ROW_NUMBER() OVER (PARTITION BY j.tagname ORDER BY j.LastActivityDate DESC, j.Score DESC) AS rn
  FROM Joined j
)
SELECT
  f.PostId,
  f.Title,
  f.Score,
  f.ViewCount,
  f.CreationDate,
  f.LastActivityDate,
  f.ScoreBand,
  f.AvgBounty,
  f.VoteCountScenario,
  f.tagname
FROM Final f
WHERE f.rn <= 5
ORDER BY f.tagname NULLS LAST, f.LastActivityDate DESC, f.Score DESC;