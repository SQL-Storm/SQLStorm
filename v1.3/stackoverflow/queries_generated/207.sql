-- {"query": "207.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4951} 
WITH q AS (
  SELECT p.*,
    string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') AS tags_arr
  FROM Posts p
  WHERE p.PostTypeId = 1
),
votes_agg AS (
  SELECT PostId,
    SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
    SUM(CASE WHEN VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes,
    COUNT(*) AS vote_total
  FROM Votes
  GROUP BY PostId
),
answers AS (
  SELECT * FROM Posts WHERE ParentId IS NOT NULL
),
answer_stats AS (
  SELECT a.ParentId,
    COUNT(*) AS ans_count,
    AVG(a.Score)::numeric AS avg_ans_score,
    array_agg(a.Score ORDER BY a.Score) AS scores_arr,
    MIN(a.CreationDate) AS first_answer_date,
    MAX(a.Score) FILTER (WHERE a.Id = (SELECT p.AcceptedAnswerId FROM Posts p WHERE p.Id = a.ParentId)) AS accepted_answer_score
  FROM answers a
  GROUP BY a.ParentId
),
answer_medians AS (
  SELECT ParentId,
    ans_count,
    avg_ans_score,
    (scores_arr[((array_length(scores_arr,1)+1)/2)])::numeric AS median_ans_score,
    first_answer_date,
    accepted_answer_score
  FROM answer_stats
),
tag_rows AS (
  SELECT q.Id AS QuestionId, t.tag AS Tag
  FROM q CROSS JOIN LATERAL (
    SELECT unnest(q.tags_arr) AS tag
  ) t
),
question_scores AS (
  SELECT q.Id,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.AnswerCount,
    COALESCE(v.upvotes,0) AS upvotes,
    COALESCE(v.downvotes,0) AS downvotes,
    COALESCE(v.favorites,0) AS favorites,
    COALESCE(a.ans_count,0) AS answer_count,
    COALESCE(a.avg_ans_score,0) AS avg_ans_score,
    COALESCE(a.median_ans_score,0) AS median_ans_score,
    COALESCE(EXTRACT(EPOCH FROM (a.first_answer_date - q.CreationDate))/3600, NULL) AS hours_to_first_answer,
    (
      (COALESCE(v.upvotes,0) - COALESCE(v.downvotes,0)) * 3.0
      + COALESCE(q.ViewCount,0) / NULLIF(GREATEST(1, COALESCE(q.AnswerCount,0)),0) * 0.5
      + COALESCE(a.avg_ans_score,0) * 2.5
      + COALESCE(v.favorites,0) * 1.8
      + (CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 50 ELSE 0 END)
      - LOG(GREATEST(1, EXTRACT(EPOCH FROM (now() - q.CreationDate))/86400 + 1)) * 2
      + (COALESCE(a.median_ans_score,0) * (CASE WHEN a.ans_count > 3 THEN 1.2 ELSE 0.8 END))
    ) AS composite_score,
    COALESCE(q.OwnerUserId, -1) AS OwnerUserId,
    COALESCE(q.Tags,'') AS Tags
  FROM q
  LEFT JOIN votes_agg v ON v.PostId = q.Id
  LEFT JOIN answer_medians a ON a.ParentId = q.Id
),
top_by_score AS (
  SELECT Id FROM question_scores ORDER BY composite_score DESC NULLS LAST LIMIT 150
),
top_by_activity AS (
  SELECT Id FROM question_scores
  ORDER BY (COALESCE(ViewCount,0) * (1 + COALESCE(answer_count,0)) + COALESCE(upvotes,0) * 10 + COALESCE(favorites,0) * 20) DESC
  LIMIT 150
),
final_ids AS (
  (SELECT Id FROM top_by_score INTERSECT SELECT Id FROM top_by_activity)
  UNION
  (SELECT Id FROM top_by_score EXCEPT SELECT Id FROM top_by_activity)
  UNION
  (SELECT Id FROM top_by_activity EXCEPT SELECT Id FROM top_by_score)
),
tag_rankings AS (
  SELECT tr.QuestionId, tr.Tag,
    ROW_NUMBER() OVER (PARTITION BY tr.Tag ORDER BY qs.composite_score DESC) AS tag_rank,
    qs.composite_score,
    qs.avg_ans_score
  FROM tag_rows tr
  LEFT JOIN question_scores qs ON qs.Id = tr.QuestionId
  WHERE tr.Tag IS NOT NULL AND tr.Tag <> ''
),
comments_recent AS (
  SELECT PostId,
    COUNT(*) FILTER (WHERE CreationDate >= now() - interval '30 days') AS recent_comments,
    COUNT(*) AS total_comments
  FROM Comments
  GROUP BY PostId
)
SELECT
  qs.Id,
  qs.Title,
  COALESCE(u.DisplayName, qs.OwnerUserId::text) AS owner_name,
  qs.ViewCount,
  qs.answer_count,
  qs.upvotes,
  qs.downvotes,
  qs.favorites,
  qs.composite_score,
  qs.hours_to_first_answer,
  qs.median_ans_score,
  COALESCE(cr.recent_comments,0) AS recent_comments,
  COALESCE(cr.total_comments,0) AS total_comments,
  (substring(qs.Title from 1 for 60) || CASE WHEN char_length(qs.Title) > 60 THEN '...' ELSE '' END) AS title_excerpt,
  (COALESCE(qs.Tags,'') || ' | score:' || to_char(qs.composite_score,'FM999999.00')) AS debug_tag_line,
  tr.tag_rank,
  tr.Tag,
  (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = qs.Id AND v.UserId IS NOT NULL) AS distinct_voters,
  (SELECT a.Id FROM Posts a WHERE a.ParentId = qs.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC LIMIT 1) AS top_answer_id,
  (CASE WHEN EXTRACT(EPOCH FROM (now() - COALESCE((SELECT LastActivityDate FROM Posts p2 WHERE p2.Id = qs.Id), qs.CreationDate)))/86400 IS NULL
     THEN -1
     ELSE FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE((SELECT LastActivityDate FROM Posts p2 WHERE p2.Id = qs.Id), qs.CreationDate)))/86400)::int
  END) AS days_since_activity
FROM question_scores qs
LEFT JOIN Users u ON u.Id = qs.OwnerUserId AND qs.OwnerUserId > 0
LEFT JOIN comments_recent cr ON cr.PostId = qs.Id
LEFT JOIN LATERAL (
  SELECT * FROM tag_rankings tr WHERE tr.QuestionId = qs.Id ORDER BY tr.tag_rank LIMIT 1
) tr ON true
WHERE qs.Id IN (SELECT Id FROM final_ids)
ORDER BY qs.composite_score DESC NULLS LAST, tr.tag_rank ASC
LIMIT 200;