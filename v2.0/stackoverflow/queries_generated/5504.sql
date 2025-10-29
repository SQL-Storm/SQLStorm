-- {"query": "5504.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 957} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Body,
    p.AcceptedAnswerId,
    p.ParentId,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
TagUsage AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount
  FROM Tags t
  JOIN Posts p ON p.Id = t.Id
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    u.LastAccessDate,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id) AS PostsByUser,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsByUser
  FROM Users u
  WHERE u.Id > 0
),
ComplexMetrics AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerUserId,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    CASE
      WHEN r.PostTypeId = 1 THEN 'Question'
      WHEN r.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    CASE
      WHEN r.ViewCount > 1000 THEN 'HighTraffic'
      WHEN r.ViewCount BETWEEN 100 AND 1000 THEN 'MediumTraffic'
      ELSE 'LowTraffic'
    END AS TrafficBand,
    (SELECT AVG(V2.BountyAmount) FROM Votes V2 WHERE V2.PostId = r.PostId AND V2.BountyAmount IS NOT NULL) AS AvgBounty,
    (SELECT COUNT(*) FROM Votes V WHERE V.PostId = r.PostId AND V.VoteTypeId = 2) AS UpVotesForPost,
    (SELECT COUNT(*) FROM Votes V WHERE V.PostId = r.PostId AND V.VoteTypeId = 3) AS DownVotesForPost,
    (SELECT STRING_AGG(CONCAT('User', U2.Id, '@', U2.DisplayName), ';')
     FROM Votes V3
     JOIN Users U2 ON U2.Id = V3.UserId
     WHERE V3.PostId = r.PostId AND V3.VoteTypeId = 2) AS UpVoters
  FROM RecentActivePosts r
),
JoinedActivity AS (
  SELECT
    cm.PostId,
    cm.Title,
    cm.OwnerUserId,
    cm.LastActivityDate,
    cm.Score,
    cm.ViewCount,
    cm.PostKind,
    cm.TrafficBand,
    cm.AvgBounty,
    cm.UpVotesForPost,
    cm.DownVotesForPost,
    cm.UpVoters,
    u.DisplayName AS OwnerDisplayName
  FROM ComplexMetrics cm
  LEFT JOIN Users u ON u.Id = cm.OwnerUserId
),
CrossJoined AS (
  SELECT
    ja.*,
    lh.Name AS HistoryTypeName,
    pg.Name AS PostHistoryGroup
  FROM JoinedActivity ja
  LEFT JOIN PostHistory ph ON ph.PostId = ja.PostId
  LEFT JOIN PostHistoryTypes lh ON ph.PostHistoryTypeId = lh.Id
  LEFT JOIN (SELECT DISTINCT Id, 'GroupA' AS Name FROM PostLinks) pg ON pg.Id = ph.PostId
),
FinalOutput AS (
  SELECT
    cj.PostId,
    cj.Title,
    cj.OwnerUserId,
    cj.OwnerDisplayName,
    cj.LastActivityDate,
    cj.Score,
    cj.ViewCount,
    cj.PostKind,
    cj.TrafficBand,
    cj.AvgBounty,
    cj.UpVotesForPost,
    cj.DownVotesForPost,
    cj.UpVoters,
    cj.HistoryTypeName,
    cj.PostHistoryGroup,
    CASE
      WHEN cj.LastActivityDate > NOW() - INTERVAL '30 days' THEN true
      ELSE false
    END AS IsRecentlyActive,
    CASE
      WHEN cj.Score >= 10 THEN 'Popular'
      WHEN cj.Score > 0 THEN 'Rising'
      ELSE 'New'
    END AS PopularityBucket
  FROM CrossJoined cj
)
SELECT *
FROM FinalOutput
ORDER BY IsRecentlyActive DESC, PopularityBucket, LastActivityDate DESC
LIMIT 100;