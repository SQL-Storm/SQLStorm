-- {"query": "392.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 15907} 
WITH
post_votes AS (
  SELECT
    "PostId",
    SUM(CASE WHEN "VoteTypeId" = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN "VoteTypeId" = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN "VoteTypeId" = 5 THEN 1 ELSE 0 END) AS favorites,
    SUM(CASE WHEN "VoteTypeId" = 1 THEN 1 ELSE 0 END) AS accept_flags,
    COUNT(*) AS total_votes
  FROM Votes
  GROUP BY "PostId"
),
questions AS (
  SELECT
    p."Id",
    p."Title",
    p."CreationDate",
    p."Score",
    p."ViewCount",
    p."AnswerCount",
    p."AcceptedAnswerId",
    p."OwnerUserId",
    p."Tags",
    p."LastActivityDate"
  FROM Posts p
  WHERE p."PostTypeId" = 1
),
question_tags AS (
  SELECT
    q."Id" AS question_id,
    q."Title",
    t.tag,
    q."CreationDate" AS q_creation,
    q."ViewCount" AS q_viewcount,
    q."Score" AS question_score,
    q."AnswerCount" AS answer_count,
    q."AcceptedAnswerId" AS accepted_answer_id,
    q."OwnerUserId" AS question_owner_id,
    q."LastActivityDate" AS question_last_activity
  FROM questions q
  LEFT JOIN LATERAL (
    SELECT unnest(
      CASE WHEN q."Tags" IS NULL OR length(q."Tags") < 3 THEN ARRAY[]::varchar[]
           ELSE string_to_array(substring(q."Tags",2,length(q."Tags")-2),'><')
      END
    ) AS tag
  ) t ON TRUE
),
answers AS (
  SELECT
    a."Id" AS answer_id,
    a."ParentId" AS question_id,
    a."OwnerUserId" AS answer_user_id,
    a."Score" AS answer_score,
    a."CreationDate" AS a_creation,
    a."LastActivityDate" AS a_last_activity,
    a."Body"
  FROM Posts a
  WHERE a."PostTypeId" = 2
),
answers_enriched AS (
  SELECT
    a.answer_id, a.question_id, a.answer_user_id, a.answer_score, a.a_creation, a.a_last_activity, a.Body,
    COALESCE(pv.upvotes,0) AS upvotes,
    COALESCE(pv.downvotes,0) AS downvotes,
    COALESCE(pv.favorites,0) AS favorites,
    qt.tag, qt.q_creation, qt.q_viewcount, qt.question_score, qt.answer_count, qt.accepted_answer_id
  FROM answers a
  LEFT JOIN post_votes pv ON pv."PostId" = a.answer_id
  LEFT JOIN question_tags qt ON qt.question_id = a.question_id
),
user_tag_stats AS (
  SELECT
    ae.tag,
    ae.answer_user_id,
    COALESCE(u."DisplayName", 'user_' || ae.answer_user_id::text) AS display_name,
    COUNT(*) AS answers_count,
    COUNT(DISTINCT ae.question_id) AS questions_answered,
    SUM(ae.upvotes) AS total_upvotes,
    SUM(ae.downvotes) AS total_downvotes,
    SUM(ae.favorites) AS total_favorites,
    SUM(CASE WHEN ae.answer_id = ae.accepted_answer_id THEN 1 ELSE 0 END) AS accepted_count,
    AVG(ae.answer_score) AS avg_answer_score,
    AVG(EXTRACT(EPOCH FROM (ae.a_creation - ae.q_creation))) AS avg_response_time_s,
    MAX(ae.a_last_activity) AS last_answer_activity,
    SUM(CASE WHEN ae.answer_score > 0 THEN 1 ELSE 0 END) AS positive_answers,
    SUM(CASE WHEN ae.answer_score <= 0 THEN 1 ELSE 0 END) AS non_positive_answers,
    MIN(ae.q_viewcount) AS min_question_views
  FROM answers_enriched ae
  LEFT JOIN Users u ON u."Id" = ae.answer_user_id
  WHERE ae.tag IS NOT NULL AND ae.tag <> ''
  GROUP BY ae.tag, ae.answer_user_id, u."DisplayName"
),
tag_stats AS (
  SELECT
    tag,
    COUNT(DISTINCT question_id) AS questions_in_tag,
    AVG(q_viewcount) AS avg_views,
    AVG(question_score) AS avg_question_score,
    AVG(answer_count) AS avg_answers_per_question
  FROM question_tags
  GROUP BY tag
),
user_badge_counts AS (
  SELECT
    b."UserId" AS user_id,
    SUM(CASE WHEN b."Class" = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b."Class" = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b."Class" = 3 THEN 1 ELSE 0 END) AS bronze_badges,
    SUM(CASE WHEN (b."TagBased"::text = '1') THEN 1 ELSE 0 END) AS tag_based_badges
  FROM Badges b
  GROUP BY b."UserId"
),
final_scores AS (
  SELECT
    uts.tag,
    uts.answer_user_id AS user_id,
    uts.display_name,
    uts.answers_count,
    uts.questions_answered,
    COALESCE(uts.total_upvotes,0) AS total_upvotes,
    COALESCE(uts.total_downvotes,0) AS total_downvotes,
    COALESCE(uts.total_favorites,0) AS total_favorites,
    uts.accepted_count,
    uts.avg_answer_score,
    uts.avg_response_time_s,
    COALESCE(ts.questions_in_tag,0) AS questions_in_tag,
    COALESCE(ts.avg_views,0) AS tag_avg_views,
    COALESCE(ubc.gold_badges,0) AS gold_badges,
    COALESCE(ubc.silver_badges,0) AS silver_badges,
    COALESCE(ubc.bronze_badges,0) AS bronze_badges,
    (
      ln(GREATEST(1, COALESCE(uts.total_upvotes,0))) * 4.0
      + sqrt(GREATEST(0, uts.answers_count)) * 2.0
      + uts.accepted_count * 25.0
      + COALESCE(uts.avg_answer_score,0) * 3.0
      + (COALESCE(ts.avg_views,0)/NULLIF(GREATEST(1, ts.questions_in_tag),0)) * 0.01
      - ln(GREATEST(1, 1 + COALESCE(uts.total_downvotes,0))) * 1.5
    )::numeric AS influence_score,
    (CASE WHEN COALESCE(uts.total_upvotes,0) = 0 THEN COALESCE(uts.total_downvotes,0)
          ELSE COALESCE(uts.total_downvotes,0)::numeric / COALESCE(uts.total_upvotes,1)::numeric END) AS controversy_index,
    (
      SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY p."Score")
      FROM Posts p
      WHERE p."PostTypeId" = 2 AND p."OwnerUserId" = uts.answer_user_id
        AND EXISTS (SELECT 1 FROM question_tags qt WHERE qt.tag = uts.tag AND qt.question_id = p."ParentId")
    ) AS median_answer_score,
    (
      SELECT COUNT(*) FROM Badges b
      WHERE b."UserId" = uts.answer_user_id AND (b."TagBased"::text = '1') AND lower(b."Name") = lower(uts.tag)
    ) AS tag_badge_count,
    lower(regexp_replace(COALESCE(uts.display_name, 'user_' || uts.answer_user_id::text) || '-' || uts.tag, '[^a-z0-9]+', '-', 'g')) AS profile_slug,
    (
      SELECT COALESCE(SUM(ae2.upvotes),0)
      FROM answers_enriched ae2
      WHERE ae2.answer_user_id = uts.answer_user_id AND ae2.tag = uts.tag
        AND ae2.a_creation >= current_timestamp - INTERVAL '90 days'
    ) AS upvotes_90d,
    (
      SELECT COALESCE(SUM(ae2.upvotes),0)
      FROM answers_enriched ae2
      WHERE ae2.answer_user_id = uts.answer_user_id AND ae2.tag = uts.tag
        AND ae2.a_creation < current_timestamp - INTERVAL '90 days'
        AND ae2.a_creation >= current_timestamp - INTERVAL '455 days'
    ) AS upvotes_prev_period
  FROM user_tag_stats uts
  LEFT JOIN tag_stats ts ON ts.tag = uts.tag
  LEFT JOIN user_badge_counts ubc ON ubc.user_id = uts.answer_user_id
),
score_ranked AS (
  SELECT fs.*,
    RANK() OVER (PARTITION BY tag ORDER BY influence_score DESC NULLS LAST) AS tag_rank,
    ROW_NUMBER() OVER (PARTITION BY tag ORDER BY influence_score DESC NULLS LAST) AS tag_rownum,
    PERCENT_RANK() OVER (PARTITION BY tag ORDER BY influence_score DESC NULLS LAST) AS pct_rank,
    DENSE_RANK() OVER (PARTITION BY tag ORDER BY answers_count DESC, total_upvotes DESC) AS activity_rank
  FROM final_scores fs
),
top_per_tag AS (
  SELECT tag, user_id, display_name, answers_count, total_upvotes, accepted_count, avg_answer_score, avg_response_time_s, influence_score, tag_rank, pct_rank, profile_slug, tag_badge_count, median_answer_score, controversy_index, 'top'::text AS source
  FROM score_ranked
  WHERE tag_rownum <= 5
),
rising_stars AS (
  SELECT tag, user_id, display_name, answers_count, total_upvotes, accepted_count, avg_answer_score, avg_response_time_s, influence_score, tag_rank, pct_rank, profile_slug, tag_badge_count, median_answer_score, controversy_index, 'rising'::text AS source
  FROM score_ranked
  WHERE upvotes_90d > COALESCE(upvotes_prev_period * 2, 1)
    AND upvotes_90d >= 5
    AND tag_rownum <= 50
)
SELECT *
FROM (
  SELECT * FROM top_per_tag
  UNION ALL
  SELECT * FROM rising_stars
) s
ORDER BY s.tag, s.influence_score DESC NULLS LAST, s.user_id;