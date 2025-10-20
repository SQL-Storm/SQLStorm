-- {"query": "240.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5482} 
WITH
GoldBadges AS (
  SELECT UserId, COUNT(*) AS GoldCount
  FROM Badges
  WHERE Class = 1
  GROUP BY UserId
),
UserStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COALESCE(gb.GoldCount, 0) AS GoldBadges
  FROM Users u
  LEFT JOIN GoldBadges gb ON gb.UserId = u.Id
),
TopQuestionPerUser AS (
  SELECT t.OwnerUserId, t.PostId, t.Title, t.ViewCount
  FROM (
    SELECT p.OwnerUserId, p.Id AS PostId, p.Title, p.ViewCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) t
  WHERE t.rn = 1
),
TopAnswerPerUser AS (
  SELECT a.OwnerUserId, a.PostId, a.Title, a.ViewCount
  FROM (
    SELECT p.OwnerUserId, p.Id AS PostId, p.Title, p.ViewCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2
  ) a
  WHERE a.rn = 1
),
CombinedSet AS (
  SELECT s.UserId, s.DisplayName, s.Reputation, s.GoldBadges,
         q.Title AS TopQuestionTitle, q.ViewCount AS TopQuestionViews,
         NULL AS TopAnswerTitle, NULL AS TopAnswerViews
  FROM UserStats s
  LEFT JOIN TopQuestionPerUser q ON q.OwnerUserId = s.UserId
  UNION ALL
  SELECT s.UserId, s.DisplayName, s.Reputation, s.GoldBadges,
         NULL AS TopQuestionTitle, NULL AS TopQuestionViews,
         a.Title AS TopAnswerTitle, a.ViewCount AS TopAnswerViews
  FROM UserStats s
  LEFT JOIN TopAnswerPerUser a ON a.OwnerUserId = s.UserId
),
Final AS (
  SELECT
     UserId,
     DisplayName,
     Reputation,
     GoldBadges,
     COALESCE(TopQuestionTitle, 'No recent question') AS TopQuestionTitle,
     TopQuestionViews,
     TopAnswerTitle,
     TopAnswerViews,
     COALESCE(TopQuestionViews, 0) + COALESCE(TopAnswerViews, 0) AS EngagementScore,
     CONCAT_WS(' | ', DisplayName,
               COALESCE(TopQuestionTitle, 'No recent question'),
               COALESCE(TopAnswerTitle, 'No recent answer')
     ) AS Summary
  FROM CombinedSet
)
SELECT *
FROM Final
ORDER BY EngagementScore DESC
LIMIT 200;