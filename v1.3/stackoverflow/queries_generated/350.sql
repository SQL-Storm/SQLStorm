-- {"query": "350.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19714} 
WITH
  recent_questions AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
           CASE WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') ELSE ARRAY[]::varchar[] END AS tag_arr,
           COALESCE(p.AnswerCount,0) AS answer_count,
           COALESCE(p.FavoriteCount,0) AS favorites,
           p.ClosedDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate IS NOT NULL
      AND p.CreationDate >= now() - interval '10 years'
  ),
  tag_expansion AS (
    SELECT rq.Id AS QuestionId, unnest(rq.tag_arr) AS Tag
    FROM recent_questions rq
  ),
  tag_popularity AS (
    SELECT te.Tag AS Tag,
           COUNT(*) AS question_count,
           SUM(COALESCE(rq.Score,0)) AS total_score,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, SUM(COALESCE(rq.Score,0)) DESC) AS tag_rank
    FROM tag_expansion te
    JOIN recent_questions rq ON te.QuestionId = rq.Id
    WHERE te.Tag IS NOT NULL AND te.Tag <> ''
    GROUP BY te.Tag
  ),
  user_post_agg AS (
    SELECT p.OwnerUserId AS user_id,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS q_count,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS a_count,
           COALESCE(SUM(p.Score),0) AS posts_score,
           MAX(p.Score) AS max_post_score
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
  ),
  user_badge_agg AS (
    SELECT b.UserId AS user_id,
           COUNT(*) AS badge_count,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
           SUM(CASE WHEN COALESCE(b.TagBased::int,0) = 1 THEN 1 ELSE 0 END) AS tag_based_badges
    FROM Badges b
    GROUP BY b.UserId
  ),
  user_activity AS (
    SELECT u.Id AS user_id,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           COALESCE(upa.q_count,0) AS q_count,
           COALESCE(upa.a_count,0) AS a_count,
           COALESCE(upa.posts_score,0) AS posts_score,
           COALESCE(upa.max_post_score,0) AS max_post_score,
           COALESCE(uba.badge_count,0) AS badge_count,
           COALESCE(uba.gold_badges,0) AS gold_badges,
           COALESCE(uba.silver_badges,0) AS silver_badges,
           COALESCE(uba.bronze_badges,0) AS bronze_badges,
           COALESCE(uba.tag_based_badges,0) AS tag_based_badges
    FROM Users u
    LEFT JOIN user_post_agg upa ON upa.user_id = u.Id
    LEFT JOIN user_badge_agg uba ON uba.user_id = u.Id
  ),
  top_answerers AS (
    SELECT user_id, DisplayName, q_count, a_count, posts_score,
           RANK() OVER (ORDER BY a_count DESC, posts_score DESC) AS answerer_rank
    FROM user_activity
    WHERE a_count > 0
  ),
  answers AS (
    SELECT a.Id AS AnswerId, a.ParentId AS QuestionId, a.OwnerUserId AS AnswererId, a.Score AS AnswerScore,
           a.CreationDate AS AnswerCreated,
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2),0) AS upvotes,
           COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id),0) AS comment_count,
           ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS rank_within_question
    FROM Posts a
    WHERE a.PostTypeId = 2
  ),
  best_answers_per_question AS (
    SELECT AnswerId, QuestionId, AnswererId, AnswerScore, upvotes, comment_count
    FROM answers
    WHERE rank_within_question = 1
  ),
  q_with_best AS (
    SELECT rq.*, bap.AnswerId, bap.AnswererId, bap.AnswerScore, bap.upvotes AS answer_upvotes, bap.comment_count AS answer_comments
    FROM recent_questions rq
    LEFT JOIN best_answers_per_question bap ON bap.QuestionId = rq.Id
  ),
  link_summary AS (
    SELECT pl.PostId,
           COUNT(*) AS total_links,
           SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicate_links,
           SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS linked_links,
           array_agg(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.RelatedPostId IS NOT NULL) AS related_ids
    FROM PostLinks pl
    GROUP BY pl.PostId
  ),
  history_edits AS (
    SELECT ph.PostId,
           COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS edit_count,
           MAX(ph.CreationDate) AS last_edit,
           array_agg(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS editors
    FROM PostHistory ph
    GROUP BY ph.PostId
  ),
  complex_scores AS (
    SELECT p.Id AS PostId, p.Title, p.OwnerUserId,
           COALESCE(p.Score,0)
           + COALESCE(LOG(GREATEST(COALESCE(p.ViewCount,0),1)),0) * 0.5
           + COALESCE(SQRT(GREATEST(v_up.upvotes,0)),0) * 1.2
           - COALESCE(v_down.downvotes,0) * 2.0
           + COALESCE(bd.badge_boost,0) * 0.05 AS composite_score,
           CASE WHEN p.ClosedDate IS NOT NULL THEN 'closed' ELSE 'open' END AS status,
           COALESCE(v_up.upvotes,0) AS upvotes,
           COALESCE(v_down.downvotes,0) AS downvotes
    FROM Posts p
    LEFT JOIN LATERAL (SELECT COUNT(*) AS upvotes FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) v_up ON true
    LEFT JOIN LATERAL (SELECT COUNT(*) AS downvotes FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) v_down ON true
    LEFT JOIN LATERAL (SELECT COALESCE(SUM(CASE WHEN b.Class = 1 THEN 5 WHEN b.Class = 2 THEN 2 WHEN b.Class = 3 THEN 1 ELSE 0 END),0) AS badge_boost FROM Badges b WHERE b.UserId = p.OwnerUserId) bd ON true
    WHERE p.PostTypeId = 1
  ),
  ranked_questions AS (
    SELECT cs.PostId, cs.Title, cs.OwnerUserId, cs.composite_score,
           ROW_NUMBER() OVER (ORDER BY cs.composite_score DESC NULLS LAST, cs.PostId) AS composite_rank
    FROM complex_scores cs
  ),
  anomaly_detection AS (
    SELECT p.Id, p.OwnerUserId, p.Score, p.ViewCount,
           CASE WHEN COALESCE(p.Score,0) < -5 AND COALESCE(p.ViewCount,0) > 1000 THEN 'low_score_high_views'
                WHEN COALESCE(p.Score,0) > 100 AND COALESCE(p.ViewCount,0) < 50 THEN 'high_score_low_views'
                ELSE NULL END AS anomaly,
           COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 12), 0) AS spam_votes
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
  ),
  high_impact_union AS (
    SELECT p.Id AS PostId FROM Posts p WHERE COALESCE(p.Score,0) > 200 OR COALESCE(p.ViewCount,0) > 100000
    UNION
    SELECT v.PostId AS PostId FROM Votes v WHERE v.VoteTypeId = 8 AND COALESCE(v.BountyAmount,0) >= 50
  ),
  high_impact_posts AS (
    SELECT PostId FROM high_impact_union
    EXCEPT
    SELECT p2.Id FROM Posts p2 WHERE p2.ClosedDate IS NOT NULL
  ),
  top_tags_per_user AS (
    SELECT u.Id AS user_id,
           ARRAY(
             SELECT te.Tag
             FROM tag_expansion te
             JOIN recent_questions rq ON rq.Id = te.QuestionId
             WHERE rq.OwnerUserId = u.Id AND te.Tag IS NOT NULL
             GROUP BY te.Tag
             ORDER BY COUNT(*) DESC, SUM(rq.Score) DESC
             LIMIT 3
           ) AS top_tags
    FROM Users u
  ),
  first_answer_times AS (
    SELECT q.Id AS question_id,
           MIN(a.CreationDate) AS first_answer_date,
           CASE WHEN MIN(a.CreationDate) IS NOT NULL THEN EXTRACT(EPOCH FROM (MIN(a.CreationDate) - q.CreationDate)) / 3600.0 ELSE NULL END AS hours_to_first_answer
    FROM recent_questions q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    GROUP BY q.Id, q.CreationDate
  )

(
  SELECT
    'question'::text AS entity_type,
    rq.Id::text AS entity_id,
    COALESCE(rq.Title, '') AS title,
    rq.OwnerUserId::text AS owner_id,
    COALESCE(u.DisplayName, '[unknown]') AS owner_name,
    COALESCE(u.Reputation,0) AS owner_reputation,
    rq.CreationDate AS creation_date,
    rq.Score::int AS score,
    rq.ViewCount::int AS view_count,
    rq.answer_count::int AS answer_count,
    COALESCE(q_with_best.AnswerId::text, '') AS best_answer_id,
    COALESCE(q_with_best.AnswerScore,0) AS best_answer_score,
    ranked_questions.composite_rank::int AS composite_rank,
    ranked_questions.composite_score::double precision AS composite_score,
    COALESCE(ls.total_links,0) AS total_links,
    COALESCE(he.edit_count,0) AS edit_count,
    COALESCE(array_to_string((SELECT ARRAY(SELECT te.Tag FROM tag_expansion te WHERE te.QuestionId = rq.Id LIMIT 3)), ','), '') AS top3_tag_sample,
    (SELECT tp.Tag FROM tag_popularity tp ORDER BY tp.question_count DESC LIMIT 1) AS top_global_tag,
    ad.anomaly AS anomaly,
    fat.hours_to_first_answer::double precision AS hours_to_first_answer,
    CASE WHEN hip.PostId IS NOT NULL THEN 'high_impact' ELSE NULL END AS special_flag,
    LEFT(REGEXP_REPLACE(COALESCE(rq.Title,''), E'[\\n\\r]+', ' ', 'g'), 200) AS snippet,
    COALESCE(ls.related_ids::text, '') AS related_ids
  FROM q_with_best rq
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
  LEFT JOIN link_summary ls ON ls.PostId = rq.Id
  LEFT JOIN history_edits he ON he.PostId = rq.Id
  LEFT JOIN ranked_questions ON ranked_questions.PostId = rq.Id
  LEFT JOIN anomaly_detection ad ON ad.Id = rq.Id
  LEFT JOIN first_answer_times fat ON fat.question_id = rq.Id
  LEFT JOIN high_impact_posts hip ON hip.PostId = rq.Id
  LEFT JOIN top_tags_per_user ttp ON ttp.user_id = u.Id
  ORDER BY COALESCE(ranked_questions.composite_score, 0) DESC NULLS LAST
  LIMIT 250
)
UNION ALL
(
  SELECT
    'user'::text AS entity_type,
    u.Id::text AS entity_id,
    COALESCE(u.DisplayName, '') AS title,
    NULL::text AS owner_id,
    COALESCE(u.DisplayName, '') AS owner_name,
    COALESCE(u.Reputation,0) AS owner_reputation,
    u.CreationDate AS creation_date,
    NULL::int AS score,
    NULL::int AS view_count,
    COALESCE(ua.a_count,0)::int AS answer_count,
    ''::text AS best_answer_id,
    NULL::int AS best_answer_score,
    NULL::int AS composite_rank,
    NULL::double precision AS composite_score,
    NULL::int AS total_links,
    NULL::int AS edit_count,
    COALESCE(array_to_string(ttp.top_tags, ','), '') AS top3_tag_sample,
    (SELECT tp.Tag FROM tag_popularity tp ORDER BY tp.question_count DESC LIMIT 1) AS top_global_tag,
    NULL::text AS anomaly,
    NULL::double precision AS hours_to_first_answer,
    CASE WHEN COALESCE(ua.q_count,0) > 100 OR COALESCE(ua.posts_score,0) > 1000 THEN 'power_user' ELSE NULL END AS special_flag,
    LEFT(REGEXP_REPLACE(COALESCE(u.AboutMe,''), E'[\\n\\r]+', ' ', 'g'), 200) AS snippet,
    NULL::text AS related_ids
  FROM Users u
  LEFT JOIN user_activity ua ON ua.user_id = u.Id
  LEFT JOIN top_tags_per_user ttp ON ttp.user_id = u.Id
  ORDER BY COALESCE(ua.posts_score,0) DESC NULLS LAST
  LIMIT 50
);