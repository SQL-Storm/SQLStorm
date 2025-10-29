-- {"query": "5934.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 868} 
WITH
-- heavy windowed metrics per user
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
    COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- correlate posts with their latest edits and history types
RecentEdits AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastEditDate,
    p.LastActivityDate,
    p.OwnerUserId,
    MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,8,9,24) THEN ph.CreationDate END) AS LastEditDateCandidate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  GROUP BY p.Id, p.Title, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.OwnerUserId
),
-- tag related performance dimension: top tags by count, with tag wiki excerpts
TagStats AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 0
),
-- synthetic workload: join across multiple optional features to stress planner
BenchmarkBoard AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(rr.LastActive, u.LastAccessDate) AS RecencyAnchor,
    ro.PostId AS RelatedPostId,
    ro.Title AS RelatedPostTitle,
    rb.LastEditDateCandidate,
    ws.TotalViews,
    ws.Upvotes,
    ws.Downvotes,
    bb.Count AS TagCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN RecentEdits ro ON ro.PostId = p.Id
  LEFT JOIN RecentEdits rb ON rb.PostId = p.Id
  LEFT JOIN UserStats ws ON ws.UserId = u.Id
  LEFT JOIN (SELECT DISTINCT TagName, Count FROM TagStats) bb ON bb.TagName LIKE CONCAT('%', ro.Title, '%')
  LEFT JOIN (SELECT MAX(LastActiveDate) AS LastActive FROM Posts WHERE OwnerUserId = u.Id) rr ON rr.LastActive IS NOT NULL
  WHERE u.Reputation > 0
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  RecencyAnchor,
  RelatedPostId,
  RelatedPostTitle,
  LastEditDateCandidate,
  TotalViews,
  Upvotes,
  Downvotes,
  TagCount,
  -- a few computed expressions to exercise NULL handling and complex predicates
  CASE WHEN LastEditDateCandidate IS NULL THEN CreationDate ELSE LastEditDateCandidate END AS BenchmarkPoint,
  CASE WHEN TagCount IS NULL THEN 0 ELSE TagCount END AS TagMetric,
  (Upvotes - Downvotes) AS NetVotes,
  (TotalViews * 1.0) / NULLIF((SELECT COUNT(*) FROM Posts WHERE OwnerUserId = UserId), 0) AS ViewsPerPost
FROM BenchmarkBoard
ORDER BY Reputation DESC, TotalViews DESC
LIMIT 100;