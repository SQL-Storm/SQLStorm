-- {"query": "173.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2418} 
WITH Questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount,
         p.OwnerUserId, u.DisplayName, u.Reputation
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= current_timestamp - interval '365 days'
),
AnswerCounts AS (
  SELECT a.ParentId AS QuestionId, COUNT(*) AS AnswerCount
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
OwnerStats AS (
  SELECT o.Id AS UserId,
         (SELECT o.DisplayName) AS DisplayName,
         o.Reputation,
         (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = o.Id AND p.CreationDate >= current_timestamp - interval '365 days') AS PostsLastYear
  FROM Users o
),
GoldBadges AS (
  SELECT b.UserId, COUNT(*) AS GoldBadges
  FROM Badges b
  WHERE b.Class = 1
  GROUP BY b.UserId
)
SELECT
  q.Id,
  q.Title,
  q.CreationDate,
  q.LastActivityDate,
  q.ViewCount,
  q.Score,
  q.Reputation AS UserReputation,
  q.DisplayName,
  COALESCE(ac.AnswerCount, 0) AS AnswerCount,
  COALESCE(gb.GoldBadges, 0) AS GoldBadges,
  COALESCE(os.PostsLastYear, 0) AS PostsLastYear,
  ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.LastActivityDate DESC) AS ActivityRank
FROM Questions q
LEFT JOIN AnswerCounts ac ON q.Id = ac.QuestionId
LEFT JOIN GoldBadges gb ON q.OwnerUserId = gb.UserId
LEFT JOIN OwnerStats os ON q.OwnerUserId = os.UserId
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 100;