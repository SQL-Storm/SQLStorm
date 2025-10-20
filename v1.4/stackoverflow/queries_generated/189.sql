-- {"query": "189.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2054} 
WITH
PostCounts AS (
  SELECT OwnerUserId AS UserId,
         COUNT(*) AS PostCount,
         AVG(Score) AS AvgScore
  FROM Posts
  GROUP BY OwnerUserId
),
LastAct AS (
  SELECT OwnerUserId AS UserId,
         MAX(COALESCE(LastActivityDate, CreationDate)) AS LastAct
  FROM Posts
  GROUP BY OwnerUserId
),
BadgeCounts AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
  FROM Badges
  GROUP BY UserId
),
TagLinked AS (
  SELECT p.OwnerUserId AS UserId,
         STRING_AGG(DISTINCT lt.Name, ',') AS LinkedTagNames
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
)
SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  pc.PostCount,
  pc.AvgScore,
  la.LastAct,
  COALESCE(bc.GoldBadges, 0) AS GoldBadges,
  COALESCE(bc.SilverBadges, 0) AS SilverBadges,
  tl.LinkedTagNames,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesGiven
FROM Users u
LEFT JOIN PostCounts pc ON pc.UserId = u.Id
LEFT JOIN LastAct la ON la.UserId = u.Id
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN TagLinked tl ON tl.UserId = u.Id

UNION ALL

SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  0 AS PostCount,
  NULL AS AvgScore,
  NULL AS LastAct,
  0 AS GoldBadges,
  0 AS SilverBadges,
  NULL AS LinkedTagNames,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesGiven
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id);