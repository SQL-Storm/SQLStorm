-- {"query": "14072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 170455, "output_tokens": 72555} 
WITH cte_active_users AS (
  SELECT u.Id, u.Reputation, u.DisplayName, u.LastAccessDate
  FROM Users u
  WHERE u.LastAccessDate >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
),
cte_question_posts AS (
  SELECT p.Id, p.PostTypeId, p.Score, p.AnswerCount, p.CreationDate, p.OwnerUserId, p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
),
cte_recent_answers AS (
  SELECT p.Id, p.ParentId, p.Score, p.CreationDate, p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 2
  AND p.CreationDate >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR)
),
cte_user_badges AS (
  SELECT b.UserId, COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
         COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
         COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges
  FROM Badges b
  GROUP BY b.UserId
)
SELECT 
  cau.Id AS user_id,
  cau.Reputation,
  cau.DisplayName,
  cau.LastAccessDate,
  COALESCE(ub.gold_badges, 0) AS gold_badges,
  COALESCE(ub.silver_badges, 0) AS silver_badges,
  COALESCE(ub.bronze_badges, 0) AS bronze_badges,
  COALESCE(qp.Id, 0) AS question_count,
  COALESCE(qp.Score, 0) AS question_score,
  COALESCE(qp.AnswerCount, 0) AS answer_count,
  COALESCE(ra.Id, 0) AS recent_answer_count,
  COALESCE(ra.Score, 0) AS recent_answer_score
FROM cte_active_users cau
LEFT JOIN cte_user_badges ub ON cau.Id = ub.UserId
LEFT JOIN cte_question_posts qp ON cau.Id = qp.OwnerUserId
LEFT JOIN cte_recent_answers ra ON cau.Id = ra.OwnerUserId
ORDER BY cau.Reputation DESC
LIMIT 100;