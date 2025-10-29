-- {"query": "5654.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 932} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.ParentId,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TagSummary AS (
  SELECT
    t.TagName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS t ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
TopActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(b.TotalBadges, 0) AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  WHERE u.Reputation > 1000
),
Engagement AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    COALESCE(vv.UpMod, 0) AS UpVotes,
    COALESCE(vv.DownMod, 0) AS DownVotes,
    p.Score,
    p.ViewCount,
    COUNT(c.Id) AS CommentCount,
    AVG(COALESCE(v.Percent, 0)) AS AvgVoteImpact
  FROM Posts p
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpMod,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownMod
    FROM Votes
    GROUP BY PostId
  ) vv ON vv.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, AVG(CASE WHEN VoteTypeId = 2 THEN 1.0 WHEN VoteTypeId = 3 THEN -1.0 ELSE 0 END) AS Percent
    FROM Votes
    WHERE VoteTypeId IN (2,3)
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2) -- questions and answers
  GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, vv.UpMod, vv.DownMod
)
SELECT
  -- combine a rich benchmarking scenario
  ro.PostId,
  ro.Title,
  ro.Tags,
  ro.CreationDate,
  ro.Score AS PostScore,
  ro.ViewCount,
  ro.OwnerUserId,
  ro.LastActivityDate,
  ro.ParentId,
  ro.PostTypeId,
  su.TagName AS MostFrequentTag,
  ta.TotalPosts,
  ta.AvgScore AS TagAvgScore,
  ta.MaxViews AS TagMaxViews,
  tcu.Id AS TopUserId,
  tcu.DisplayName AS TopUserName,
  tcu.Reputation AS TopUserRep,
  e.UpVotes,
  e.DownVotes,
  e.CommentCount,
  e.AvgVoteImpact,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ro.OwnerUserId AND p2.LastActivityDate > ro.LastActivityDate) AS RecentActivityByOwner,
  (CASE
     WHEN ro.LastEditDate IS NULL THEN NULL
     ELSE EXTRACT(EPOCH FROM ro.LastEditDate - ro.CreationDate) / 3600.0
   END) AS HoursFromCreationToLastEdit
FROM RecentHot ro
LEFT JOIN TagSummary ta ON TRUE
LEFT JOIN TopActiveUsers tcu ON tcu.Id = ro.OwnerUserId
LEFT JOIN Engagement e ON e.PostId = ro.PostId
ORDER BY ro.LastActivityDate DESC
LIMIT 100;