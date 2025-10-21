-- {"query": "266.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9441} 
WITH
RecentEdits AS (
  SELECT ph.PostId, COUNT(*) AS EditCount
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,12,13,14,15,16,19,20,33,34,50,52,53,66)
  GROUP BY ph.PostId
),
ActivePosts AS (
  SELECT p.Id, p.OwnerUserId, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate,
         p.LastActivityDate, p.Tags, p.CommentCount,
         COALESCE(re.EditCount, 0) AS EditCount
  FROM Posts p
  LEFT JOIN RecentEdits re ON re.PostId = p.Id
  WHERE p.PostTypeId = 1
),
UserStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(ap.Id) AS PostCount,
         COALESCE(SUM(ap.Score),0) AS ScoreSum,
         MAX(ap.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN ActivePosts ap ON ap.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Ranked AS (
  SELECT us.*, ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY COALESCE(us.ScoreSum,0) DESC, COALESCE(us.PostCount,0) DESC) AS rn
  FROM UserStats us
),
TopActive AS (
  SELECT r.UserId, r.DisplayName, r.Reputation, r.PostCount, r.ScoreSum, r.LastActivity,
         CASE WHEN EXISTS (SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = r.UserId AND p3.LastActivityDate > cast('2024-10-01' as date) - INTERVAL '30 days') THEN true ELSE false END AS HasRecent,
         CASE WHEN r.ScoreSum > 1000 THEN 'Excellent' WHEN r.ScoreSum > 100 THEN 'Strong' ELSE 'New' END AS ScoreBand,
         SUBSTR(r.DisplayName, 1, 1) AS FirstChar
  FROM Ranked r
  WHERE r.rn = 1
),
HighRep AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation, 0 AS PostCount, 0 AS ScoreSum, u.LastAccessDate AS LastActivity,
         false AS HasRecent,
         CASE WHEN 0 > 1000 THEN 'Excellent' WHEN 0 > 100 THEN 'Strong' ELSE 'New' END AS ScoreBand,
         SUBSTR(u.DisplayName, 1, 1) AS FirstChar
  FROM Users u
  WHERE u.Reputation > 10000
),
Final AS (
  SELECT UserId, DisplayName, Reputation, PostCount, ScoreSum, LastActivity, HasRecent, ScoreBand, FirstChar
  FROM TopActive
  UNION ALL
  SELECT UserId, DisplayName, Reputation, PostCount, ScoreSum, LastActivity, HasRecent, ScoreBand, FirstChar
  FROM HighRep
)
SELECT *
FROM Final
ORDER BY LastActivity DESC NULLS LAST
LIMIT 100;