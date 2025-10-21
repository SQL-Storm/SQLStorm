-- {"query": "225.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9757} 
WITH
BaseUsers AS (
  SELECT Id, DisplayName, Reputation
  FROM Users
),
Q1 AS (
  SELECT DISTINCT u.Id
  FROM BaseUsers u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
),
Q2 AS (
  SELECT DISTINCT u.Id
  FROM BaseUsers u
  JOIN Badges b ON b.UserId = u.Id
),
Intersected AS (
  SELECT Id FROM Q1
  INTERSECT
  SELECT Id FROM Q2
),
RecentStats AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(*) AS PostCount_90,
         AVG(p.Score) AS AvgScore_90
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
  GROUP BY p.OwnerUserId
),
BadgeStats AS (
  SELECT b.UserId, COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
LastEdit AS (
  SELECT p.OwnerUserId AS UserId, MAX(ph.CreationDate) AS LastEditDate
  FROM PostHistory ph
  JOIN Posts p ON p.Id = ph.PostId
  WHERE ph.PostHistoryTypeId IN (4,5,6,10,11)
  GROUP BY p.OwnerUserId
),
FirstTagPerUser AS (
  SELECT DISTINCT ON (p.OwnerUserId) p.OwnerUserId AS UserId,
         (string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'))[1] AS FirstTag,
         p.CreationDate
  FROM Posts p
  WHERE p.Tags IS NOT NULL
  ORDER BY p.OwnerUserId, p.CreationDate ASC
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(rs.PostCount_90, 0) AS PostCount_Last90,
  ROW_NUMBER() OVER (ORDER BY COALESCE(rs.PostCount_90, 0) DESC) AS Rank_Last90,
  COALESCE(rs.AvgScore_90, 0) AS AvgScore_Last90,
  COALESCE(bs.BadgeCount, 0) AS Badges,
  le.LastEditDate,
  ft.FirstTag,
  (SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     JOIN Posts pp ON pp.Id = ph.PostId
     WHERE pp.OwnerUserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS LastEditDate_Correlated,
  CASE WHEN COALESCE(rs.PostCount_90, 0) > 0 OR COALESCE(bs.BadgeCount, 0) > 0 THEN TRUE ELSE FALSE END AS Active
FROM Intersected i
JOIN Users u ON u.Id = i.Id
LEFT JOIN RecentStats rs ON rs.UserId = u.Id
LEFT JOIN BadgeStats bs ON bs.UserId = u.Id
LEFT JOIN LastEdit le ON le.UserId = u.Id
LEFT JOIN FirstTagPerUser ft ON ft.UserId = u.Id
ORDER BY Rank_Last90
LIMIT 100;