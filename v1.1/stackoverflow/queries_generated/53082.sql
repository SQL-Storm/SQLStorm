-- {"query": "53082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 649} 

WITH question_tags AS (
  SELECT p.Id AS question_id, 
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag,
         p.CreationDate AS question_date,
         p.Score AS question_score
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01'
),
answer_details AS (
  SELECT a.Id AS answer_id,
         a.ParentId,
         a.OwnerUserId,
         a.Score,
         a.CreationDate,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS comment_count
  FROM Posts a
  WHERE a.PostTypeId = 2
),
user_answers AS (
  SELECT ad.OwnerUserId, 
         qt.tag, 
         COUNT(ad.answer_id) AS answer_count, 
         AVG(ad.Score) AS avg_score, 
         SUM(ad.comment_count) AS total_comments,
         MAX(ad.CreationDate) AS last_answer_date
  FROM answer_details ad
  JOIN question_tags qt ON ad.ParentId = qt.question_id
  GROUP BY ad.OwnerUserId, qt.tag
),
top_users_per_tag AS (
  SELECT tag, 
         OwnerUserId, 
         answer_count, 
         avg_score, 
         total_comments,
         last_answer_date,
         ROW_NUMBER() OVER (PARTITION BY tag ORDER BY answer_count DESC, avg_score DESC, total_comments DESC) AS rn
  FROM user_answers
),
gold_badges AS (
  SELECT Name AS tag, 
         COUNT(*) AS gold_count,
         MAX(Date) AS latest_gold_date
  FROM Badges
  WHERE Class = 1 AND TagBased = true
  GROUP BY Name
),
tag_stats AS (
  SELECT qt.tag, 
         COUNT(DISTINCT qt.question_id) AS question_count, 
         AVG(qt.question_score) AS avg_question_score,
         MAX(qt.question_date) AS latest_question_date
  FROM question_tags qt
  GROUP BY qt.tag
  HAVING COUNT(DISTINCT qt.question_id) > 1000
)
SELECT ts.tag, 
       ts.question_count, 
       ts.avg_question_score, 
       ts.latest_question_date,
       tup.OwnerUserId, 
       u.DisplayName, 
       u.Reputation, 
       tup.answer_count, 
       tup.avg_score, 
       tup.total_comments,
       tup.last_answer_date,
       gb.gold_count,
       gb.latest_gold_date,
       (SELECT COUNT(*) FROM Votes v 
        JOIN Posts p ON v.PostId = p.Id 
        WHERE p.OwnerUserId = tup.OwnerUserId AND p.PostTypeId = 2 AND v.VoteTypeId = 2) AS total_upvotes
FROM tag_stats ts
JOIN top_users_per_tag tup ON ts.tag = tup.tag AND tup.rn = 1
JOIN Users u ON tup.OwnerUserId = u.Id
LEFT JOIN gold_badges gb ON ts.tag = gb.tag
ORDER BY ts.question_count DESC, ts.avg_question_score DESC
LIMIT 50;
