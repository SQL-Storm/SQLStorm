-- {"query": "159.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2611} 
WITH
PostAgg AS (
  SELECT OwnerUserId,
         Count(*) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
         Count(*) FILTER (WHERE PostTypeId = 2) AS AnswerCount,
         AVG(Score) AS AvgScore,
         MAX(LastEditDate) AS LastPostEdit
  FROM Posts
  GROUP BY OwnerUserId
),
BadgeAgg AS (
  SELECT UserId, Count(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
),
VoteAgg AS (
  SELECT p.OwnerUserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.OwnerUserId
),
LastEditByUser AS (
  SELECT p.OwnerUserId, MAX(ph.CreationDate) AS LastEditDate
  FROM PostHistory ph
  JOIN Posts p ON p.Id = ph.PostId
  WHERE ph.PostHistoryTypeId IN (10, 16, 22) -- close, moved/merged, etc.
  GROUP BY p.OwnerUserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(pa.QuestionCount, 0) AS QuestionCount,
  COALESCE(pa.AnswerCount, 0) AS AnswerCount,
  COALESCE(pa.AvgScore, 0) AS AvgScore,
  COALESCE(ba.BadgeCount, 0) AS BadgeCount,
  COALESCE(va.UpVotes, 0) AS UpVotes,
  COALESCE(va.DownVotes, 0) AS DownVotes,
  COALESCE(lu.LastEditDate, u.LastAccessDate) AS LastActivityDate
FROM Users u
LEFT JOIN PostAgg pa ON pa.OwnerUserId = u.Id
LEFT JOIN BadgeAgg ba ON ba.UserId = u.Id
LEFT JOIN VoteAgg va ON va.OwnerUserId = u.Id
LEFT JOIN LastEditByUser lu ON lu.OwnerUserId = u.Id
ORDER BY UpVotes DESC, Reputation DESC
LIMIT 300;