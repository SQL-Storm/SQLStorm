WITH question_tags AS (
  SELECT 
    p.Id AS question_id, 
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag,
    p.CreationDate,
    p.ViewCount,
    p.Score AS question_score
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= '2015-01-01'
),
answer_info AS (
  SELECT 
    a.ParentId AS question_id, 
    a.OwnerUserId AS user_id, 
    a.Score AS answer_score, 
    a.CreationDate AS answer_date,
    CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS is_accepted,
    (EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 86400.0) AS response_time
  FROM Posts a
  JOIN Posts q ON a.ParentId = q.Id
  WHERE a.PostTypeId = 2
),
user_contributions AS (
  SELECT 
    qt.tag, 
    ai.user_id, 
    COUNT(*) AS answer_count, 
    SUM(ai.answer_score) AS total_answer_score, 
    AVG(ai.answer_score) AS avg_answer_score,
    SUM(ai.is_accepted) AS accepted_count,
    AVG(CASE WHEN ai.is_accepted = 1 THEN ai.response_time ELSE NULL END) AS avg_accepted_response_time,
    COUNT(DISTINCT qt.question_id) AS unique_questions_answered
  FROM question_tags qt
  JOIN answer_info ai ON qt.question_id = ai.question_id
  WHERE ai.answer_date >= '2015-01-01'
  GROUP BY qt.tag, ai.user_id
  HAVING COUNT(*) >= 5
),
badge_info AS (
  SELECT 
    b.UserId, 
    COUNT(*) AS total_badges, 
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS tag_badges
  FROM Badges b
  GROUP BY b.UserId
),
ranked_contributions AS (
  SELECT 
    uc.*, 
    u.DisplayName, 
    u.Reputation,
    bi.total_badges,
    bi.gold_badges,
    bi.silver_badges,
    bi.tag_badges,
    ROW_NUMBER() OVER (PARTITION BY uc.tag ORDER BY uc.total_answer_score DESC, uc.answer_count DESC) AS rank_within_tag,
    RANK() OVER (PARTITION BY uc.tag ORDER BY uc.avg_answer_score DESC) AS avg_score_rank
  FROM user_contributions uc
  JOIN Users u ON uc.user_id = u.Id
  LEFT JOIN badge_info bi ON uc.user_id = bi.UserId
  WHERE u.Reputation >= 1000
),
top_tags AS (
  SELECT 
    tag, 
    COUNT(DISTINCT question_id) AS question_count,
    SUM(ViewCount) AS total_views,
    AVG(question_score) AS avg_question_score
  FROM question_tags
  GROUP BY tag
  HAVING COUNT(DISTINCT question_id) >= 1000
  ORDER BY COUNT(DISTINCT question_id) DESC
  LIMIT 50
)
SELECT 
  tt.tag, 
  tt.question_count, 
  tt.total_views,
  tt.avg_question_score,
  rc.user_id, 
  rc.DisplayName, 
  rc.Reputation, 
  rc.answer_count, 
  rc.total_answer_score, 
  rc.avg_answer_score,
  rc.accepted_count,
  rc.avg_accepted_response_time,
  rc.unique_questions_answered,
  rc.total_badges,
  rc.gold_badges,
  rc.silver_badges,
  rc.tag_badges,
  rc.rank_within_tag,
  rc.avg_score_rank
FROM top_tags tt
JOIN ranked_contributions rc ON tt.tag = rc.tag
WHERE rc.rank_within_tag <= 10
ORDER BY tt.question_count DESC, rc.rank_within_tag ASC;