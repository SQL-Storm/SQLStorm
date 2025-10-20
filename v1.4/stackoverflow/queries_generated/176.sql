-- {"query": "176.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1327} 
WITH
recent_questions AS (
  SELECT Id AS PostId, OwnerUserId, CreationDate
  FROM Posts
  WHERE PostTypeId = 1
    AND CreationDate > now() - interval '30 days'
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(rq.PostId) AS Questions30,
    MAX(rq.CreationDate) AS LastQuestionDate
  FROM Users u
  LEFT JOIN recent_questions rq ON rq.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_counts AS (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
),
upvotes AS (
  SELECT p.OwnerUserId, COUNT(*) AS Upvotes
  FROM Posts p
  JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  GROUP BY p.OwnerUserId
),
combined AS (
  SELECT
    t.UserId,
    t.DisplayName,
    t.Reputation,
    t.Questions30,
    t.LastQuestionDate,
    COALESCE(b.BadgeCount, 0) AS BadgeCount,
    COALESCE(u.Upvotes, 0) AS Upvotes
  FROM top_users t
  LEFT JOIN badge_counts b ON b.UserId = t.UserId
  LEFT JOIN upvotes u ON u.OwnerUserId = t.UserId
)
SELECT
  c.*,
  ROW_NUMBER() OVER (ORDER BY c.Reputation DESC, c.Questions30 DESC) AS rn
FROM combined c
ORDER BY c.Reputation DESC, c.Questions30 DESC
LIMIT 100;