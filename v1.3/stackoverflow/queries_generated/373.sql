-- {"query": "373.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17587} 
WITH
tags_in_tags_table AS (
  SELECT lower(trim(TagName)) AS tag
  FROM Tags
  WHERE TagName IS NOT NULL
),
tags_in_posts AS (
  SELECT DISTINCT lower(trim(unnested_tag)) AS tag
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags)-2), '><')) AS unnested_tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  ) x
),
new_potential_tags AS (
  SELECT tag FROM tags_in_posts
  EXCEPT
  SELECT tag FROM tags_in_tags_table
),
common_tags AS (
  SELECT tag FROM tags_in_posts
  INTERSECT
  SELECT tag FROM tags_in_tags_table
),
all_tags AS (
  SELECT tag FROM tags_in_tags_table
  UNION
  SELECT tag FROM tags_in_posts
),
question_tags AS (
  SELECT
    q.Id AS question_id,
    q.AcceptedAnswerId,
    q.OwnerUserId AS asker_id,
    q.CreationDate AS question_date,
    q.Score AS q_score,
    q.ViewCount,
    q.Title,
    lower(trim(unnest(string_to_array(substring(q.Tags,2,char_length(q.Tags)-2),'><')))) AS tag
  FROM Posts q
  WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
),
answer_posts AS (
  SELECT a.Id AS answer_id, a.ParentId AS question_id, a.OwnerUserId AS answerer_id, a.CreationDate AS answer_date, a.Score AS a_score
  FROM Posts a
  WHERE a.PostTypeId = 2
),
tagged_answers AS (
  SELECT
    qt.tag,
    ap.answer_id,
    ap.answerer_id,
    ap.question_id,
    ap.a_score,
    qt.AcceptedAnswerId AS accepted_answer_id,
    ap.answer_date
  FROM answer_posts ap
  JOIN question_tags qt ON qt.question_id = ap.question_id
),
post_votes AS (
  SELECT p.Id AS post_id,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
),
post_comments AS (
  SELECT PostId, COUNT(*) AS comment_count, MAX(CreationDate) AS last_comment_date
  FROM Comments
  GROUP BY PostId
),
link_agg AS (
  SELECT pl.PostId AS post_id,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicate_outbound,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS linked_count
  FROM PostLinks pl
  GROUP BY pl.PostId
),
post_edits AS (
  SELECT ph.PostId, COUNT(*) AS edit_count, MAX(ph.CreationDate) AS last_edit_date
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,24)
  GROUP BY ph.PostId
),
q_agg_per_tag AS (
  SELECT
    qt.tag,
    COUNT(DISTINCT qt.question_id) AS question_count,
    AVG(qt.q_score) AS avg_question_score,
    SUM(COALESCE(pv.upvotes,0)) AS total_question_upvotes,
    SUM(COALESCE(pc.comment_count,0)) AS total_question_comments,
    SUM(COALESCE(la.duplicate_outbound,0)) AS total_question_duplicates,
    SUM(COALESCE(pe.edit_count,0)) AS total_question_edits,
    SUM(qt.ViewCount) AS total_views,
    COUNT(DISTINCT qt.asker_id) AS unique_askers,
    MIN(qt.question_date) AS first_question_date,
    MAX(qt.question_date) AS last_question_date,
    array_agg(qt.title ORDER BY qt.q_score DESC) FILTER (WHERE qt.title IS NOT NULL) AS top_question_titles
  FROM question_tags qt
  LEFT JOIN post_votes pv ON pv.post_id = qt.question_id
  LEFT JOIN post_comments pc ON pc.PostId = qt.question_id
  LEFT JOIN link_agg la ON la.post_id = qt.question_id
  LEFT JOIN post_edits pe ON pe.PostId = qt.question_id
  GROUP BY qt.tag
),
a_agg_per_tag AS (
  SELECT
    ta.tag,
    COUNT(ta.answer_id) AS answer_count,
    AVG(ta.a_score) AS avg_answer_score,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY ta.a_score) AS median_answer_score,
    SUM(COALESCE(pv.upvotes,0)) AS total_answer_upvotes,
    SUM(COALESCE(pv.downvotes,0)) AS total_answer_downvotes,
    SUM(COALESCE(pc.comment_count,0)) AS total_answer_comments,
    SUM(COALESCE(pe.edit_count,0)) AS total_answer_edits,
    SUM(CASE WHEN ta.answer_id = ta.accepted_answer_id THEN 1 ELSE 0 END) AS accepted_answer_count,
    COUNT(DISTINCT ta.answerer_id) AS unique_answerers,
    MAX(ta.answer_date) AS last_answer_date,
    array_agg(ta.answer_id ORDER BY ta.a_score DESC) FILTER (WHERE ta.answer_id IS NOT NULL) AS top_answer_ids
  FROM tagged_answers ta
  LEFT JOIN post_votes pv ON pv.post_id = ta.answer_id
  LEFT JOIN post_comments pc ON pc.PostId = ta.answer_id
  LEFT JOIN post_edits pe ON pe.PostId = ta.answer_id
  GROUP BY ta.tag
),
tag_top_contributor AS (
  SELECT t.tag,
    ua.answerer_id AS top_answerer_id,
    ua.total_score AS top_answerer_score,
    ua.answer_count AS top_answerer_answers
  FROM all_tags t
  LEFT JOIN LATERAL (
    SELECT ta.answerer_id, SUM(ta.a_score) AS total_score, COUNT(*) AS answer_count
    FROM tagged_answers ta
    WHERE ta.tag = t.tag AND ta.answerer_id IS NOT NULL
    GROUP BY ta.answerer_id
    ORDER BY total_score DESC NULLS LAST, answer_count DESC
    LIMIT 1
  ) ua ON true
),
tag_badges AS (
  SELECT t.tag,
    (SELECT COUNT(*) FROM Badges b WHERE lower(b.Name) = t.tag) AS badge_count,
    (SELECT AVG(b.Class) FROM Badges b WHERE lower(b.Name) = t.tag) AS avg_badge_class
  FROM all_tags t
),
final_tag_stats AS (
  SELECT
    t.tag,
    COALESCE(q.question_count,0) AS question_count,
    COALESCE(a.answer_count,0) AS answer_count,
    COALESCE(q.avg_question_score,0) AS avg_question_score,
    COALESCE(a.avg_answer_score,0) AS avg_answer_score,
    COALESCE(a.median_answer_score,0) AS median_answer_score,
    COALESCE(a.accepted_answer_count,0) AS accepted_answer_count,
    CASE WHEN COALESCE(a.answer_count,0) > 0 THEN (COALESCE(a.accepted_answer_count,0)::numeric / a.answer_count) ELSE 0 END AS accepted_rate,
    COALESCE(q.total_question_upvotes,0) AS total_question_upvotes,
    COALESCE(a.total_answer_upvotes,0) AS total_answer_upvotes,
    COALESCE(q.total_question_downvotes,0) AS total_question_downvotes,
    COALESCE(a.total_answer_downvotes,0) AS total_answer_downvotes,
    (COALESCE(q.total_question_upvotes,0) + COALESCE(a.total_answer_upvotes,0)) AS total_upvotes,
    (COALESCE(q.total_question_downvotes,0) + COALESCE(a.total_answer_downvotes,0)) AS total_downvotes,
    COALESCE(q.total_question_comments,0) + COALESCE(a.total_answer_comments,0) AS total_comments,
    COALESCE(q.total_question_duplicates,0) AS total_duplicates_out,
    COALESCE(q.total_question_edits,0) + COALESCE(a.total_answer_edits,0) AS total_edits,
    COALESCE(q.total_views,0) AS total_views,
    COALESCE(q.unique_askers,0) AS unique_askers,
    COALESCE(a.unique_answerers,0) AS unique_answerers,
    COALESCE(q.top_question_titles, ARRAY[]::varchar[]) AS top_question_titles,
    COALESCE(a.top_answer_ids, ARRAY[]::int[]) AS top_answer_ids,
    COALESCE(ttc.top_answerer_id, NULL) AS top_answerer_id,
    COALESCE(ttc.top_answerer_score,0) AS top_answerer_score,
    COALESCE(ttc.top_answerer_answers,0) AS top_answerer_answers,
    COALESCE(tb.badge_count,0) AS badge_count,
    COALESCE(tb.avg_badge_class,0) AS avg_badge_class,
    COALESCE(GREATEST(q.last_question_date, a.last_answer_date), q.last_question_date, a.last_answer_date, NOW()) AS last_activity_date,
    COALESCE(q.first_question_date, NOW()) AS first_question_date,
    COALESCE(LEAST(NULLIF(q.total_views,0),1000000),0)::numeric AS scaled_views,
    (COALESCE(a.avg_answer_score,0) * 2.0 + COALESCE(q.avg_question_score,0))
      * (1 + 0.75 * CASE WHEN COALESCE(a.answer_count,0)>0 THEN (a.accepted_answer_count::numeric / a.answer_count) ELSE 0 END)
      * LOG(GREATEST(1, COALESCE(q.total_views,1)) + 1)
      * sqrt(GREATEST(1, COALESCE(q.question_count,1)))
      / NULLIF(1 + COALESCE(q.total_question_duplicates,0), 0) AS raw_quality_score
  FROM all_tags t
  LEFT JOIN q_agg_per_tag q ON q.tag = t.tag
  LEFT JOIN a_agg_per_tag a ON a.tag = t.tag
  LEFT JOIN tag_top_contributor ttc ON ttc.tag = t.tag
  LEFT JOIN tag_badges tb ON tb.tag = t.tag
),
ranked_tags AS (
  SELECT
    f.*,
    EXP(-GREATEST(EXTRACT(EPOCH FROM (NOW() - f.last_activity_date))/86400,0) / 365.0) AS recency_weight,
    (f.raw_quality_score * EXP(-GREATEST(EXTRACT(EPOCH FROM (NOW() - f.last_activity_date))/86400,0) / 365.0)) AS composite_score
  FROM final_tag_stats f
)
SELECT
  rt.tag,
  rt.question_count,
  rt.answer_count,
  rt.avg_question_score,
  rt.avg_answer_score,
  rt.median_answer_score,
  rt.accepted_answer_count,
  ROUND(rt.accepted_rate::numeric,3) AS accepted_rate,
  rt.total_upvotes,
  rt.total_downvotes,
  rt.total_comments,
  rt.total_duplicates_out,
  rt.total_edits,
  rt.total_views,
  rt.unique_askers,
  rt.unique_answerers,
  rt.badge_count,
  ROUND(rt.avg_badge_class::numeric,3) AS avg_badge_class,
  rt.top_answerer_id,
  u.DisplayName AS top_answerer_name,
  u.Reputation AS top_answerer_reputation,
  rt.top_answerer_score,
  rt.top_answerer_answers,
  rt.first_question_date,
  rt.last_activity_date,
  rt.recency_weight,
  rt.raw_quality_score,
  rt.composite_score,
  RANK() OVER (ORDER BY rt.composite_score DESC NULLS LAST) AS tag_rank,
  CASE WHEN rt.tag IN (SELECT tag FROM common_tags) THEN true ELSE false END AS is_in_tags_table,
  CASE WHEN rt.tag IN (SELECT tag FROM new_potential_tags) THEN true ELSE false END AS only_in_posts_not_in_tags_table,
  (SELECT array_agg(qid) FROM (SELECT qt.question_id AS qid FROM question_tags qt WHERE qt.tag = rt.tag ORDER BY qt.q_score DESC NULLS LAST LIMIT 5) _q) AS sample_top_question_ids,
  (SELECT array_agg(aid) FROM (SELECT ta.answer_id AS aid FROM tagged_answers ta WHERE ta.tag = rt.tag ORDER BY ta.a_score DESC NULLS LAST LIMIT 5) _a) AS sample_top_answer_ids,
  (SELECT AVG(s.a_score) FROM (SELECT ta2.a_score FROM tagged_answers ta2 WHERE ta2.tag = rt.tag ORDER BY ta2.answer_date DESC NULLS LAST LIMIT 50) s) AS avg_recent_50_answer_score,
  initcap(replace(rt.tag, '-', ' ')) AS printable_tag,
  left(coalesce(array_to_string(rt.top_question_titles, ' | '), ''), 240) AS top_titles_snippet
FROM ranked_tags rt
LEFT JOIN Users u ON u.Id = rt.top_answerer_id
ORDER BY rt.composite_score DESC NULLS LAST
LIMIT 200;