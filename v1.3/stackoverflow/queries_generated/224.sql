-- {"query": "224.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4988} 
WITH
recent_questions AS (
  SELECT p.*,
    (SELECT count(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= current_date - INTERVAL '5 years'
),
tags_exploded AS (
  SELECT q.Id AS QuestionId, trim(t.tag) AS tag
  FROM recent_questions q
  CROSS JOIN LATERAL unnest(
    CASE 
      WHEN q.Tags IS NULL THEN ARRAY[]::text[] 
      ELSE string_to_array(substring(q.Tags,2,length(q.Tags)-2),'><') 
    END
  ) AS t(tag)
),
tag_stats AS (
  SELECT te.tag,
    count(*) AS questions_with_tag,
    sum(q.ViewCount) AS total_views,
    avg(q.Score) AS avg_q_score
  FROM tags_exploded te
  JOIN recent_questions q ON q.Id = te.QuestionId
  GROUP BY te.tag
),
answer_aggregates AS (
  SELECT ParentId AS QuestionId,
    count(*) AS answer_count,
    sum(CASE WHEN Score>0 THEN 1 ELSE 0 END) AS positive_answers,
    avg(Score) AS avg_answer_score,
    max(Score) AS max_answer_score,
    min(Score) AS min_answer_score,
    count(distinct OwnerUserId) AS unique_answerers
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY ParentId
),
accepted_info AS (
  SELECT q.Id AS QuestionId, q.AcceptedAnswerId, 
    aa.OwnerUserId AS AcceptedOwnerUserId,
    aa.Score AS AcceptedScore,
    extract(epoch from (aa.CreationDate - q.CreationDate))/3600.0 AS hours_to_accept
  FROM recent_questions q
  LEFT JOIN Posts aa ON aa.Id = q.AcceptedAnswerId
),
user_metrics AS (
  SELECT u.Id AS UserId, u.Reputation,
    count(distinct p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS posts_count,
    sum(coalesce(p.Score,0)) AS total_post_score,
    avg(coalesce(p.Score,0)) AS avg_post_score,
    (SELECT count(*) FROM Badges b WHERE b.UserId=u.Id AND b.Class=1) AS gold_badges,
    (SELECT count(*) FROM Badges b WHERE b.UserId=u.Id AND b.Class=2) AS silver_badges,
    (SELECT count(*) FROM Badges b WHERE b.UserId=u.Id AND b.Class=3) AS bronze_badges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.Reputation
),
question_enrichment AS (
  SELECT q.*,
    coalesce(aa.answer_count,0) AS answer_count,
    coalesce(aa.avg_answer_score,0) AS avg_answer_score,
    ai.hours_to_accept,
    ai.AcceptedAnswerId,
    coalesce(ui.Reputation,0) AS owner_rep,
    coalesce(ui.gold_badges,0) AS owner_gold,
    (SELECT count(*) FROM Comments c WHERE c.PostId=q.Id AND c.CreationDate >= q.CreationDate) AS comments_since_creation,
    (SELECT count(*) FROM Votes v WHERE v.PostId=q.Id AND v.VoteTypeId=2) AS upvotes,
    (SELECT count(*) FROM Votes v WHERE v.PostId=q.Id AND v.VoteTypeId=3) AS downvotes,
    (SELECT string_agg(distinct t.tag, ',' ORDER BY t.tag) FROM tags_exploded t WHERE t.QuestionId = q.Id) AS tag_list,
    CASE WHEN q.Tags IS NULL THEN true ELSE false END AS is_untagged
  FROM recent_questions q
  LEFT JOIN answer_aggregates aa ON aa.QuestionId = q.Id
  LEFT JOIN accepted_info ai ON ai.QuestionId = q.Id
  LEFT JOIN Users ui ON ui.Id = q.OwnerUserId
),
high_impact_questions AS (
  SELECT qe.*,
    ts.tag,
    ts.questions_with_tag,
    ts.total_views,
    row_number() OVER (PARTITION BY ts.tag ORDER BY qe.ViewCount DESC) AS per_tag_rank,
    dense_rank() OVER (ORDER BY (qe.Score + coalesce(qe.avg_answer_score,0)*0.5 + qe.comments_since_creation*0.1) DESC) AS global_impact_rank
  FROM question_enrichment qe
  LEFT JOIN tags_exploded te ON qe.Id = te.QuestionId
  LEFT JOIN tag_stats ts ON ts.tag = te.tag
  WHERE (qe.ViewCount > 1000 OR qe.Score >= 10 OR qe.answer_count >= 5)
),
top_by_views AS (
  SELECT qe.Id AS QuestionId, qe.Title, 'views' AS reason, qe.ViewCount AS metric
  FROM question_enrichment qe
  WHERE qe.ViewCount > (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY ViewCount) FROM question_enrichment)
  ORDER BY qe.ViewCount DESC
  LIMIT 100
),
top_by_score AS (
  SELECT qe.Id AS QuestionId, qe.Title, 'score' AS reason, qe.Score AS metric
  FROM question_enrichment qe
  WHERE qe.Score > (SELECT coalesce(nullif(max(Score),0),1) * 0.5 FROM question_enrichment)
  ORDER BY qe.Score DESC
  LIMIT 100
),
union_top AS (
  SELECT * FROM top_by_views
  UNION
  SELECT * FROM top_by_score
),
final_candidates AS (
  SELECT hq.*,
    ut.metric, ut.reason,
    (SELECT count(*) FROM Users u WHERE u.Id = (SELECT aa.OwnerUserId FROM Posts aa WHERE aa.Id = hq.AcceptedAnswerId) AND u.Reputation > 20000) AS accepted_by_highrep,
    EXISTS(SELECT 1 FROM PostHistory ph WHERE ph.PostId = hq.Id AND ph.PostHistoryTypeId IN (10,12)) AS has_close_or_delete_history,
    (hq.Score * 3 + coalesce(hq.avg_answer_score,0)*2 + coalesce(hq.comments_since_creation,0) - coalesce(hq.downvotes,0)) AS synthetic_score
  FROM high_impact_questions hq
  LEFT JOIN union_top ut ON ut.QuestionId = hq.Id
  WHERE (hq.tag_list IS NOT NULL OR hq.is_untagged)
),
ranked_final AS (
  SELECT *,
    row_number() OVER (PARTITION BY coalesce(tag_list,'[untagged]') ORDER BY synthetic_score DESC, ViewCount DESC) AS tag_group_rank,
    rank() OVER (ORDER BY synthetic_score DESC) AS overall_rank
  FROM final_candidates
)
SELECT rf.overall_rank,
  rf.Id AS QuestionId,
  left(rf.Title,200) AS TitleSnippet,
  coalesce(rf.tag_list, '[untagged]') AS Tags,
  rf.owner_rep,
  rf.owner_gold,
  rf.answer_count,
  rf.avg_answer_score,
  rf.comments_since_creation,
  rf.ViewCount,
  rf.Score,
  rf.hours_to_accept,
  rf.accepted_by_highrep > 0 AS AcceptedByHighRep,
  rf.has_close_or_delete_history,
  rf.synthetic_score,
  rf.per_tag_rank,
  rf.global_impact_rank,
  (SELECT u.DisplayName FROM Users u WHERE u.Id = (SELECT ph.UserId FROM PostHistory ph WHERE ph.PostId = rf.Id AND ph.UserId IS NOT NULL ORDER BY ph.CreationDate DESC LIMIT 1)) AS LastEditorName,
  substring(coalesce(rf.tag_list,'[untagged]') || ' :: ' || coalesce(rf.Title,'') FROM 1 FOR 150) AS summary,
  CASE WHEN rf.hours_to_accept IS NULL THEN 'never accepted' WHEN rf.hours_to_accept < 24 THEN 'quick' ELSE 'slow' END AS acceptance_speed
FROM ranked_final rf
WHERE rf.overall_rank <= 250
ORDER BY rf.overall_rank;