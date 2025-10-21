-- {"query": "125.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1201} 
WITH activity AS (
  SELECT
    p.OwnerUserId AS UserId,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsLastYear,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersLastYear
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY p.OwnerUserId
),
badge_count AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesOwned
  FROM Badges b
  GROUP BY b.UserId
),
last_post AS (
  SELECT
    p.OwnerUserId AS UserId,
    MAX(p.CreationDate) AS LastPostDate
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY p.OwnerUserId
),
sum_scores AS (
  SELECT
    p.OwnerUserId AS UserId,
    SUM(p.Score) AS SumScoresLastYear
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY p.OwnerUserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(a.QuestionsLastYear, 0) AS QuestionsLastYear,
  COALESCE(a.AnswersLastYear, 0) AS AnswersLastYear,
  COALESCE(bc.BadgesOwned, 0) AS BadgesOwned,
  COALESCE(ss.SumScoresLastYear, 0) AS SumScoresLastYear,
  lu.LastPostDate
FROM Users u
LEFT JOIN activity a ON a.UserId = u.Id
LEFT JOIN badge_count bc ON bc.UserId = u.Id
LEFT JOIN sum_scores ss ON ss.UserId = u.Id
LEFT JOIN last_post lu ON lu.UserId = u.Id
ORDER BY SumScoresLastYear DESC, BadgesOwned DESC, UserId
LIMIT 200;