-- {"query": "5024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1323} 
WITH
-- Find the top 100 tags by usage
top_tags AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count
  FROM
    Tags t
  WHERE
    t.IsModeratorOnly = 0 OR t.IsModeratorOnly IS NULL
  ORDER BY
    t.Count DESC
  LIMIT 100
),
-- For each tag, compute question, answer, comment, and user metrics
tag_metrics AS (
  SELECT
    tt.TagName,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
    SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS total_question_views,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_question_score,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS avg_answer_score,
    COUNT(DISTINCT c.Id) AS comment_count,
    COUNT(DISTINCT p.OwnerUserId) FILTER (WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0) AS unique_askers
  FROM
    top_tags tt
    LEFT JOIN Posts p ON (p.Tags IS NOT NULL AND '<' || tt.TagName || '>' = ANY (string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')))
    LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY
    tt.TagName
),
-- Find the most "influential" user per tag by answers and score
tag_top_user AS (
  SELECT
    tt.TagName,
    u.Id AS user_id,
    u.DisplayName,
    COUNT(a.Id) AS answers_given,
    SUM(a.Score) AS total_answer_score,
    DENSE_RANK() OVER (PARTITION BY tt.TagName ORDER BY COUNT(a.Id) DESC, SUM(a.Score) DESC NULLS LAST, u.Reputation DESC) AS user_rank
  FROM
    top_tags tt
    JOIN Posts q ON (q.Tags IS NOT NULL AND q.PostTypeId = 1 AND '<' || tt.TagName || '>' = ANY (string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')))
    JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
  WHERE
    a.OwnerUserId IS NOT NULL AND a.OwnerUserId > 0
  GROUP BY
    tt.TagName, u.Id, u.DisplayName, u.Reputation
),
-- Get close reasons statistics per tag, including NULL logic for missing close reasons
tag_closure_stats AS (
  SELECT
    tt.TagName,
    cr.Name AS close_reason,
    COUNT(DISTINCT ph.PostId) AS closed_questions,
    COUNT(DISTINCT CASE WHEN cr.Name IS NULL THEN ph.PostId END) AS unknown_reason_count
  FROM
    top_tags tt
    JOIN Posts q ON (q.Tags IS NOT NULL AND q.PostTypeId = 1 AND '<' || tt.TagName || '>' = ANY (string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')))
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr ON cr.Id = NULLIF(ph.Comment, '')::int
  GROUP BY
    tt.TagName, cr.Name
),
-- Users with a sharp reputation drop (lost at least 100 rep between two consecutive posts in the tag)
rep_drops AS (
  SELECT DISTINCT
    tt.TagName,
    u.Id AS user_id,
    u.DisplayName,
    lead(u.Reputation) OVER (PARTITION BY tt.TagName, u.Id ORDER BY p.CreationDate) AS next_rep,
    u.Reputation AS curr_rep,
    (u.Reputation - lead(u.Reputation) OVER (PARTITION BY tt.TagName, u.Id ORDER BY p.CreationDate)) AS rep_delta
  FROM
    top_tags tt
    JOIN Posts p ON (p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
                     AND '<' || tt.TagName || '>' = ANY (string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')))
    JOIN Users u ON p.OwnerUserId = u.Id
)
-- Final combined metrics per tag
SELECT
  tm.TagName,
  tm.question_count,
  tm.answer_count,
  tm.total_question_views,
  tm.avg_question_score,
  tm.avg_answer_score,
  tm.comment_count,
  tm.unique_askers,
  (SELECT tu.DisplayName FROM tag_top_user tu WHERE tu.TagName = tm.TagName AND tu.user_rank = 1 LIMIT 1) AS top_answerer,
  (SELECT tu.total_answer_score FROM tag_top_user tu WHERE tu.TagName = tm.TagName AND tu.user_rank = 1 LIMIT 1) AS top_answerer_total_score,
  COALESCE((SELECT SUM(closed_questions) FROM tag_closure_stats cs WHERE cs.TagName = tm.TagName AND cs.close_reason = 'Duplicate'), 0) AS duplicate_closures,
  COALESCE((SELECT SUM(closed_questions) FROM tag_closure_stats cs WHERE cs.TagName = tm.TagName AND cs.close_reason = 'Off-topic'), 0) AS offtopic_closures,
  COALESCE((SELECT SUM(unknown_reason_count) FROM tag_closure_stats cs WHERE cs.TagName = tm.TagName), 0) AS unknown_closure_reasons,
  COUNT(rd.user_id) FILTER (WHERE rd.rep_delta >= 100) AS users_with_rep_drop
FROM
  tag_metrics tm
  LEFT JOIN rep_drops rd ON rd.TagName = tm.TagName
GROUP BY
  tm.TagName,
  tm.question_count,
  tm.answer_count,
  tm.total_question_views,
  tm.avg_question_score,
  tm.avg_answer_score,
  tm.comment_count,
  tm.unique_askers
ORDER BY
  tm.total_question_views DESC, tm.TagName
LIMIT 30;