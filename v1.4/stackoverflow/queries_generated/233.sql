-- {"query": "233.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 13691} 
WITH
PostsTT AS (
  SELECT p.Id,
         p.PostTypeId,
         t.Name AS PostTypeName,
         p.Title,
         p.Tags,
         p.Score,
         p.ViewCount,
         p.CreationDate,
         p.LastActivityDate,
         p.OwnerUserId,
         p.OwnerDisplayName
  FROM Posts p
  LEFT JOIN PostTypes t ON p.PostTypeId = t.Id
),
UserInfo AS (
  SELECT Id AS UserId, DisplayName, Location
  FROM Users
),
UserStats AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(p.Id) AS TotalPosts,
         SUM(p.Score) AS TotalScore
  FROM Posts p
  GROUP BY p.OwnerUserId
),
BadgeCounts AS (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
),
UpVotes AS (
  SELECT PostId, COUNT(*) AS UpVotes
  FROM Votes
  WHERE VoteTypeId = 2
  GROUP BY PostId
),
CommentCounts AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
LastEditor AS (
  SELECT p.Id AS PostId, u.DisplayName AS LastEditorName
  FROM Posts p
  LEFT JOIN Users u ON p.LastEditorUserId = u.Id
)
SELECT
  pt.Id AS PostId,
  pt.PostTypeId,
  pt.PostTypeName,
  pt.Title,
  pt.Tags,
  pt.Score,
  pt.ViewCount,
  pt.CreationDate,
  pt.LastActivityDate,
  ui.DisplayName AS OwnerDisplayName,
  ui.Location AS Location,
  COALESCE(bc.BadgeCount, 0) AS BadgeCount,
  COALESCE(uv.UpVotes, 0) AS UpVotes,
  COALESCE(us.TotalScore, 0) AS UserTotalScore,
  DATEDIFF(minute, pt.CreationDate, GETDATE()) AS AgeMinutes,
  ROW_NUMBER() OVER (PARTITION BY pt.OwnerUserId ORDER BY pt.LastActivityDate DESC) AS RankWithinOwner,
  le.LastEditorName,
  COALESCE(cc.CommentCount, 0) AS CommentCount,
  CONCAT('Post ', pt.Id, ' - ', pt.Title) AS MetaString,
  (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = pt.OwnerUserId) AS AverageOwnerScore
FROM PostsTT pt
LEFT JOIN UserInfo ui ON ui.UserId = pt.OwnerUserId
LEFT JOIN UserStats us ON us.UserId = pt.OwnerUserId
LEFT JOIN BadgeCounts bc ON bc.UserId = pt.OwnerUserId
LEFT JOIN UpVotes uv ON uv.PostId = pt.Id
LEFT JOIN CommentCounts cc ON cc.PostId = pt.Id
LEFT JOIN LastEditor le ON le.PostId = pt.Id
WHERE pt.LastActivityDate > DATEADD(day, -14, GETDATE())

UNION ALL

SELECT
  pt.Id AS PostId,
  pt.PostTypeId,
  pt.PostTypeName,
  pt.Title,
  pt.Tags,
  pt.Score,
  pt.ViewCount,
  pt.CreationDate,
  pt.LastActivityDate,
  ui.DisplayName AS OwnerDisplayName,
  ui.Location AS Location,
  COALESCE(bc.BadgeCount, 0) AS BadgeCount,
  COALESCE(uv.UpVotes, 0) AS UpVotes,
  COALESCE(us.TotalScore, 0) AS UserTotalScore,
  DATEDIFF(minute, pt.CreationDate, GETDATE()) AS AgeMinutes,
  ROW_NUMBER() OVER (PARTITION BY pt.OwnerUserId ORDER BY pt.LastActivityDate DESC) AS RankWithinOwner,
  NULL AS LastEditorName,
  COALESCE(cc.CommentCount, 0) AS CommentCount,
  CONCAT('Archived Post ', pt.Id, ' - ', pt.Title) AS MetaString,
  (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = pt.OwnerUserId) AS AverageOwnerScore
FROM PostsTT pt
LEFT JOIN UserInfo ui ON ui.UserId = pt.OwnerUserId
LEFT JOIN UserStats us ON us.UserId = pt.OwnerUserId
LEFT JOIN BadgeCounts bc ON bc.UserId = pt.OwnerUserId
LEFT JOIN UpVotes uv ON uv.PostId = pt.Id
LEFT JOIN CommentCounts cc ON cc.PostId = pt.Id
WHERE pt.LastActivityDate <= DATEADD(day, -14, GETDATE())
ORDER BY AgeMinutes DESC;