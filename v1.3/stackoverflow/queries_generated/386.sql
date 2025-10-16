-- {"query": "386.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 10127} 
WITH
question_base AS (
    SELECT p.id AS question_id,
           p.title,
           p.body,
           p.creationdate,
           p.score,
           p.viewcount,
           p.owneruserid,
           u.displayname AS ownername,
           u.reputation,
           u.creationdate AS ownercreated,
           p.answercount,
           p.commentcount,
           p.favoritecount,
           p.closeddate,
           -- tags as array of text
           CASE WHEN p.tags IS NULL THEN ARRAY[]::text[] ELSE string_to_array(substring(p.tags FROM 2 FOR char_length(p.tags)-2), '><') END AS tags,
           COALESCE((string_to_array(substring(p.tags FROM 2 FOR char_length(p.tags)-2), '><'))[1], '<<none>>') AS primary_tag,
           COALESCE(p.score::numeric,0) + COALESCE(p.viewcount,0)/1000.0 AS hotness,
           extract(epoch FROM (now() - p.creationdate)) AS age_seconds
    FROM posts p
    LEFT JOIN users u ON p.owneruserid = u.id
    WHERE p.posttypeid = 1
),
votes_agg AS (
    SELECT v.postid,
           SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
           SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
           SUM(CASE WHEN v.votetypeid = 1 THEN 1 ELSE 0 END) AS accepted_by_originator,
           SUM(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS favorites
    FROM votes v
    GROUP BY v.postid
),
answers_agg AS (
    SELECT p.parentid AS question_id,
           COUNT(*) FILTER (WHERE p.posttypeid = 2) AS answer_count_calc,
           COALESCE(AVG(p.score) FILTER (WHERE p.posttypeid = 2),0) AS avg_answer_score,
           MAX(p.score) FILTER (WHERE p.posttypeid = 2) AS max_answer_score,
           SUM(CASE WHEN p.score >= 0 THEN 1 ELSE 0 END) FILTER (WHERE p.posttypeid = 2) AS nonneg_answers
    FROM posts p
    WHERE p.posttypeid = 2
    GROUP BY p.parentid
),
comments_agg AS (
    SELECT c.postid,
           COUNT(*) AS comment_count_calc,
           AVG(c.score) AS avg_comment_score,
           BOOL_OR(c.userid IS NULL) AS has_anonymous_comment
    FROM comments c
    GROUP BY c.postid
),
badges_by_user AS (
    SELECT b.userid,
           COUNT(*) AS badge_count,
           SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badges,
           SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_badges,
           SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
           SUM(CASE WHEN b.tagbased = TRUE THEN 1 ELSE 0 END) AS tag_based_badges
    FROM badges b
    GROUP BY b.userid
),
postlinks_agg AS (
    SELECT pl.postid,
           COUNT(*) FILTER (WHERE pl.linktypeid = 1) AS linked_count,
           COUNT(*) FILTER (WHERE pl.linktypeid = 3) AS duplicate_count,
           COUNT(*) AS total_links
    FROM postlinks pl
    GROUP BY pl.postid
),
edits AS (
    SELECT ph.postid,
           COUNT(*) AS edits,
           MAX(ph.creationdate) AS last_edit,
           MIN(ph.creationdate) AS first_edit,
           MAX(ph.creationdate) - MIN(ph.creationdate) AS edit_span,
           (array_agg(ph.userid ORDER BY ph.creationdate DESC))[1] AS last_editor_id,
           (array_agg(ph.userdisplayname ORDER BY ph.creationdate DESC))[1] AS last_editor_name,
           (array_agg(ph.posthistorytypeid ORDER BY ph.creationdate DESC))[1] AS last_history_type
    FROM posthistory ph
    GROUP BY ph.postid
),
tag_exploded AS (
    SELECT q.question_id,
           unnest(q.tags) AS tag
    FROM question_base q
),
tag_metrics AS (
    SELECT t.tag,
           COUNT(DISTINCT t.question_id) AS questions_with_tag,
           AVG(q.score) AS avg_score_for_tag,
           SUM(q.viewcount) AS total_views_for_tag
    FROM tag_exploded t
    JOIN question_base q ON q.question_id = t.question_id
    GROUP BY t.tag
),
top_answers_per_question AS (
    SELECT a.question_id,
           string_agg(a.sn, '||' ORDER BY a.score DESC, a.answer_id) AS top3_answers
    FROM (
        SELECT p.parentid AS question_id,
               p.id AS answer_id,
               p.score AS score,
               substring(coalesce(p.body,'' ) FROM 1 FOR 120) AS snippet,
               ('#' || p.id || ':' || p.score || ':' || replace(replace(substring(coalesce(p.body,'' ) FROM 1 FOR 30), E'\n',' '), E'\r',' ')) AS sn,
               ROW_NUMBER() OVER (PARTITION BY p.parentid ORDER BY p.score DESC NULLS LAST, p.creationdate ASC) AS rn
        FROM posts p
        WHERE p.posttypeid = 2
    ) a
    WHERE a.rn <= 3
    GROUP BY a.question_id
),
user_stats AS (
    SELECT u.id AS user_id,
           u.displayname,
           u.reputation,
           COALESCE(b.badge_count,0) AS badge_count,
           COALESCE(b.gold_badges,0) AS gold_badges,
           COALESCE(b.silver_badges,0) AS silver_badges,
           COALESCE(b.bronze_badges,0) AS bronze_badges,
           (SELECT COUNT(*) FROM posts p2 WHERE p2.owneruserid = u.id AND p2.posttypeid = 1) AS questions_posted,
           (SELECT COUNT(*) FROM posts p2 WHERE p2.owneruserid = u.id AND p2.posttypeid = 2) AS answers_posted,
           (SELECT COALESCE(AVG(p2.score),0) FROM posts p2 WHERE p2.owneruserid = u.id AND p2.posttypeid = 2) AS avg_answer_score_by_user
    FROM users u
    LEFT JOIN badges_by_user b ON b.userid = u.id
),
question_enriched AS (
    SELECT q.*,
           v.upvotes, v.downvotes, v.accepted_by_originator, v.favorites,
           a.answer_count_calc, a.avg_answer_score, a.max_answer_score,
           c.comment_count_calc, c.avg_comment_score, c.has_anonymous_comment,
           COALESCE(pl.linked_count,0) AS linked_count,
           COALESCE(pl.duplicate_count,0) AS duplicate_count,
           COALESCE(pl.total_links,0) AS total_links,
           e.edits, e.last_edit, e.first_edit, e.edit_span, e.last_editor_id, e.last_editor_name, e.last_history_type,
           t.top3_answers,
           u2.badge_count AS owner_badge_count,
           u2.gold_badges AS owner_gold,
           u2.silver_badges AS owner_silver,
           u2.bronze_badges AS owner_bronze,
           -- correlated computed columns
           (SELECT COUNT(*) FROM posts p2 WHERE p2.owneruserid = q.owneruserid AND p2.posttypeid = 1) AS owner_question_count,
           (SELECT COUNT(*) FROM votes v2 WHERE v2.userid = q.owneruserid) AS votes_cast_by_owner,
           (SELECT COALESCE(SUM(p2.score),0) FROM posts p2 WHERE p2.parentid = q.question_id) AS sum_answer_scores,
           (SELECT COUNT(*) FROM postlinks pl2 WHERE pl2.relatedpostid = q.question_id AND pl2.linktypeid = 3) AS duplicates_pointing_to_me
    FROM question_base q
    LEFT JOIN votes_agg v ON v.postid = q.question_id
    LEFT JOIN answers_agg a ON a.question_id = q.question_id
    LEFT JOIN comments_agg c ON c.postid = q.question_id
    LEFT JOIN postlinks_agg pl ON pl.postid = q.question_id
    LEFT JOIN edits e ON e.postid = q.question_id
    LEFT JOIN top_answers_per_question t ON t.question_id = q.question_id
    LEFT JOIN user_stats u2 ON u2.user_id = q.owneruserid
),
ranked_questions AS (
    SELECT qe.*,
           RANK() OVER (ORDER BY COALESCE(qe.score,0) DESC, COALESCE(qe.viewcount,0) DESC) AS global_rank,
           ROW_NUMBER() OVER (PARTITION BY qe.primary_tag ORDER BY COALESCE(qe.score,0) DESC, COALESCE(qe.viewcount,0) DESC) AS tag_rank,
           SUM(COALESCE(qe.viewcount,0)) OVER (PARTITION BY qe.primary_tag) AS tag_total_views,
           AVG(COALESCE(qe.score,0)) OVER (PARTITION BY qe.primary_tag) AS tag_avg_score,
           (COALESCE(qe.score,0)::numeric / NULLIF(EXTRACT(EPOCH FROM (now() - qe.creationdate))/86400.0,0)) AS score_per_day
    FROM question_enriched qe
),
fresh_set AS (
    SELECT * FROM ranked_questions
    WHERE creationdate >= now() - INTERVAL '90 days'
      AND (answercount >= 1 OR COALESCE(answer_count_calc,0) >= 1)
      AND (score >= 0 OR viewcount > 1000)
),
stale_set AS (
    SELECT * FROM ranked_questions
    WHERE creationdate < now() - INTERVAL '365 days'
      AND (COALESCE(answer_count_calc,0) = 0 OR score < 0 OR (viewcount > 5000 AND score < 5))
),
combined AS (
    SELECT 'fresh' AS cohort, * FROM fresh_set
    UNION ALL
    SELECT 'stale' AS cohort, * FROM stale_set
),
final_prep AS (
    SELECT c.cohort,
           c.question_id,
           c.title,
           c.primary_tag,
           c.tags,
           c.score,
           c.viewcount,
           COALESCE(c.answer_count_calc,0) AS answer_count_calc,
           COALESCE(c.upvotes,0) AS upvotes,
           COALESCE(c.downvotes,0) AS downvotes,
           COALESCE(c.comment_count_calc,0) AS comment_count_calc,
           COALESCE(c.edits,0) AS edits,
           c.owner_badge_count,
           c.owner_gold,
           c.owner_silver,
           c.owner_bronze,
           c.last_edit,
           c.edit_span,
           c.top3_answers,
           c.sum_answer_scores,
           c.duplicates_pointing_to_me,
           c.global_rank,
           c.tag_rank,
           c.tag_total_views,
           c.tag_avg_score,
           c.score_per_day,
           -- complex synthetic score combining many factors
           (
               COALESCE(c.score,0) * 3
               + log(GREATEST(COALESCE(c.viewcount,0),1)::numeric) * 2
               + COALESCE(c.upvotes,0) * 1.5
               - COALESCE(c.downvotes,0) * 2
               + COALESCE(c.answer_count_calc,0) * 4
               + COALESCE(c.comment_count_calc,0) * 0.5
               + COALESCE(c.owner_badge_count,0) * 0.2
               + (CASE WHEN c.closeddate IS NULL THEN 10 ELSE -100 END)
               - (extract(epoch FROM COALESCE(c.edit_span, INTERVAL '0 seconds'))/86400.0) * 0.1
               + (CASE WHEN c.duplicates_pointing_to_me > 0 THEN 20 ELSE 0 END)
           ) AS composite_hotness,
           COALESCE(NULLIF(c.score,0), NULLIF(c.upvotes,0), 1) AS primary_signal,
           (COALESCE(c.score,0) - COALESCE(c.downvotes,0))::int % GREATEST(1, COALESCE(c.answer_count_calc,0)) AS score_mod_answers
    FROM combined c
),
final_ranked AS (
    SELECT fp.*,
           RANK() OVER (PARTITION BY fp.cohort ORDER BY fp.composite_hotness DESC NULLS LAST) AS cohort_rank,
           NTILE(10) OVER (PARTITION BY fp.cohort ORDER BY fp.composite_hotness DESC) AS decile_in_cohort
    FROM final_prep fp
)
SELECT fr.cohort,
       fr.cohort_rank,
       fr.decile_in_cohort,
       fr.question_id,
       fr.title,
       fr.primary_tag,
       fr.tags,
       fr.score,
       fr.viewcount,
       fr.answer_count_calc,
       fr.upvotes,
       fr.downvotes,
       fr.comment_count_calc,
       fr.edits,
       fr.owner_badge_count,
       fr.last_edit,
       fr.edit_span,
       fr.top3_answers,
       fr.sum_answer_scores,
       fr.duplicates_pointing_to_me,
       fr.global_rank,
       fr.tag_rank,
       fr.tag_total_views,
       fr.tag_avg_score,
       round(fr.score_per_day::numeric,4) AS score_per_day,
       round(fr.composite_hotness::numeric,4) AS composite_hotness,
       fr.primary_signal,
       fr.score_mod_answers
FROM final_ranked fr
ORDER BY fr.cohort, fr.cohort_rank
LIMIT 500;