-- {"query": "5370.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 704} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerDisplayName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    row_number() OVER (ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TagStats AS (
  SELECT
    t.TagName,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.CreationDate) AS LastCreated
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
  GROUP BY t.TagName
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(p.Id) > 5
),
PerformanceBench AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.OwnerDisplayName,
    rh.CreationDate,
    rh.Score,
    rh.ViewCount,
    rs.TotalViews,
    rs.AvgScore,
    tc.UserId AS TopUserId,
    tc.DisplayName AS TopUserName,
    tc.Reputation AS TopUserRep,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LastUpVoteDate,
    STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN CAST(v.UserId AS TEXT) END, ',') AS UpVoteUserIds
  FROM RecentHot rh
  LEFT JOIN TagStats rs ON rh.Title LIKE '%' || rs.TagName || '%'
  LEFT JOIN Votes v ON v.PostId = rh.PostId
  LEFT JOIN TopContributors tc ON TRUE
  GROUP BY
    rh.PostId, rh.Title, rh.OwnerDisplayName, rh.CreationDate, rh.Score, rh.ViewCount, rs.TotalViews, rs.AvgScore, tc.UserId, tc.DisplayName, tc.Reputation
)
SELECT
  p.PostId,
  p.Title,
  p.OwnerDisplayName,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.TotalViews,
  p.AvgScore,
  p.TopUserId,
  p.TopUserName,
  p.TopUserRep,
  p.UpVotes,
  p.DownVotes,
  p.LastUpVoteDate,
  p.UpVoteUserIds,
  CASE
    WHEN p.TotalViews > 1000 THEN 'Hot'
    WHEN p.TotalViews > 500 THEN 'Warm'
    ELSE 'New'
  END AS ViewTier
FROM PerformanceBench p
ORDER BY p.TotalViews DESC NULLS LAST, p.CreationDate DESC
LIMIT 100;