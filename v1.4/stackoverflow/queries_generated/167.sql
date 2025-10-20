-- {"query": "167.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1633} 
WITH recent_questions AS (
  SELECT p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
user_activity AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
         MAX(rq.CreationDate) AS LastQuestionDate,
         COALESCE(SUM(rq.Score), 0) AS TotalQuestionScore,
         COUNT(rq.Id) AS QuestionCount
  FROM Users u
  LEFT JOIN recent_questions rq ON rq.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_summary AS (
  SELECT b.UserId, COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
vote_summary AS (
  SELECT p.OwnerUserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
         MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.OwnerUserId
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.LastQuestionDate,
  ua.TotalQuestionScore,
  ua.QuestionCount,
  COALESCE(bs.BadgeCount, 0) AS BadgeCount,
  COALESCE(vs.Upvotes, 0) AS Upvotes,
  COALESCE(vs.Downvotes, 0) AS Downvotes,
  vs.LastVoteDate,
  MAX(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId) AS LastActivity
FROM user_activity ua
LEFT JOIN badge_summary bs ON bs.UserId = ua.UserId
LEFT JOIN vote_summary vs ON vs.OwnerUserId = ua.UserId
LEFT JOIN Posts p ON p.OwnerUserId = ua.UserId
WHERE ua.QuestionCount > 0
ORDER BY ua.Reputation DESC NULLS LAST
LIMIT 200;