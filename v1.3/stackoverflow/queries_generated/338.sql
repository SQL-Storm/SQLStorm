-- {"query": "338.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 13495} 
WITH
question_tags AS (
  SELECT p.Id AS PostId,
         trim(t.tag) AS TagName
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND length(p.Tags) > 2
),
votes_per_post AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
         SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_by_originator,
         COUNT(*) AS votes_total,
         AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - v.CreationDate))/86400.0) AS avg_vote_age_days,
         MAX(v.CreationDate) AS last_vote_date
  FROM Votes v
  GROUP BY v.PostId
),
comments_per_post AS (
  SELECT p.Id AS PostId,
         COUNT(c.Id) AS comment_count,
         MAX(c.CreationDate) AS last_comment_date,
         SUM(CASE WHEN COALESCE(c.Score,0) > 0 THEN 1 ELSE 0 END) AS positive_comments
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id
),
post_history_agg AS (
  SELECT ph.PostId,
         MAX(ph.CreationDate) AS last_history_date,
         MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS last_close_reason_text,
         SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS close_votes_total,
         SUM(CASE WHEN ph.PostHistoryTypeId IN (24,52) THEN 1 ELSE 0 END) AS edits_or_hot_events
  FROM PostHistory ph
  GROUP BY ph.PostId
),
post_links_agg AS (
  SELECT pl.PostId,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS outbound_links,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS outbound_duplicate_marks,
         SUM(CASE WHEN pl.RelatedPostId IS NOT NULL THEN 1 ELSE 0 END) AS related_count
  FROM PostLinks pl
  GROUP BY pl.PostId
),
links_pointing_to AS (
  SELECT pl.RelatedPostId AS PostId,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS inbound_duplicate_marks,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS inbound_links
  FROM PostLinks pl
  GROUP BY pl.RelatedPostId
),
owner_stats AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS total_posts,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_count,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
         COALESCE(MAX(b.Date), to_timestamp(0)) AS last_badge_date,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
         AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId = 2) AS avg_answer_score_by_user
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation
),
top_commenters_per_post AS (
  SELECT c.PostId, c.UserId,
         RANK() OVER (PARTITION BY c.PostId ORDER BY SUM(COALESCE(c.Score,0)) DESC, COUNT(*) DESC) AS commenter_rank,
         SUM(COALESCE(c.Score,0)) AS commenter_score_sum,
         COUNT(*) AS commenter_count
  FROM Comments c
  GROUP BY c.PostId, c.UserId
),
top_commenters AS (
  SELECT t.PostId, t.UserId, t.commenter_score_sum, t.commenter_count
  FROM top_commenters_per_post t
  WHERE t.commenter_rank = 1
),
question_enriched AS (
  SELECT p.Id,
         p.Title,
         COALESCE(p.OwnerUserId, -1) AS OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.AcceptedAnswerId,
         COALESCE(p.Body,'') AS Body,
         qt.TagName,
         COALESCE(v.upvotes,0) AS post_upvotes,
         COALESCE(v.downvotes,0) AS post_downvotes,
         COALESCE(v.favorites,0) AS post_favorites,
         COALESCE(cp.comment_count,0) AS comment_count,
         COALESCE(pl.outbound_duplicate_marks,0) AS outbound_duplicate_marks,
         COALESCE(lpt.inbound_duplicate_marks,0) AS inbound_duplicate_marks,
         COALESCE(ph.close_votes_total,0) AS close_votes_total,
         COALESCE(ph.last_close_reason_text,NULL) AS last_close_reason_text,
         COALESCE(os.Reputation,0) AS owner_reputation,
         os.total_posts AS owner_total_posts,
         os.gold_badges, os.silver_badges, os.bronze_badges,
         COALESCE(tc.UserId, NULL) AS top_commenter_id,
         COALESCE(tc.commenter_score_sum,0) AS top_commenter_influence,
         ROW_NUMBER() OVER (PARTITION BY qt.TagName ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS tag_score_rank,
         COUNT(*) OVER (PARTITION BY qt.TagName) AS tag_total_questions,
         AVG(p.Score) OVER (PARTITION BY qt.TagName) AS tag_avg_score,
         SUM(COALESCE(v.upvotes,0)) OVER (PARTITION BY qt.TagName) AS tag_total_upvotes,
         NTILE(10) OVER (ORDER BY p.Score DESC NULLS LAST) AS decile_by_score,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS per_owner_latest_rank,
         p.LastActivityDate,
         COALESCE(LENGTH(p.Body),0) AS body_length,
         COALESCE(LENGTH(REGEXP_REPLACE(COALESCE(p.Title,''),'[^A-Za-z0-9]+',' ','g')),0) AS title_char_length,
         COALESCE(array_length(regexp_split_to_array(COALESCE(p.Title,''), '[^A-Za-z0-9]+'),1),0) AS title_word_count
  FROM Posts p
  JOIN question_tags qt ON qt.PostId = p.Id
  LEFT JOIN votes_per_post v ON v.PostId = p.Id
  LEFT JOIN comments_per_post cp ON cp.PostId = p.Id
  LEFT JOIN post_links_agg pl ON pl.PostId = p.Id
  LEFT JOIN links_pointing_to lpt ON lpt.PostId = p.Id
  LEFT JOIN post_history_agg ph ON ph.PostId = p.Id
  LEFT JOIN owner_stats os ON os.UserId = p.OwnerUserId
  LEFT JOIN top_commenters tc ON tc.PostId = p.Id
  WHERE p.PostTypeId = 1
),
tag_aggregates AS (
  SELECT TagName,
         COUNT(*) AS tag_question_count,
         AVG(ViewCount) AS tag_avg_views,
         AVG(tag_avg_score) AS tag_avg_score_of_questions,
         SUM(post_upvotes) AS tag_sum_upvotes,
         MAX(post_upvotes) AS tag_max_upvotes,
         SUM(comment_count) AS tag_sum_comments
  FROM question_enriched
  GROUP BY TagName
),
scored_questions AS (
  SELECT qe.*,
         (COALESCE(qe.Score,0)::double precision * 3.0
          + LOG(1 + GREATEST(qe.ViewCount,0)::double precision) * 2.0
          + SQRT(GREATEST(qe.post_upvotes - qe.post_downvotes,0)) * 4.0
          + LEAST(500, GREATEST(qe.owner_reputation,0)) / 50.0
          + COALESCE(qe.tag_avg_score,0) * 1.5
          - (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - qe.CreationDate))/86400.0) * 0.02
         ) AS computed_metric
  FROM question_enriched qe
),
scored_ranked AS (
  SELECT sq.*,
         RANK() OVER (PARTITION BY sq.TagName ORDER BY sq.computed_metric DESC) AS tag_metric_rank,
         RANK() OVER (ORDER BY sq.computed_metric DESC) AS global_metric_rank
  FROM scored_questions sq
)
SELECT
  'QUESTION'::text AS entity_type,
  sr.Id AS entity_id,
  sr.Title AS title_or_name,
  sr.TagName AS primary_tag,
  sr.OwnerUserId AS owner_id,
  sr.owner_reputation AS owner_reputation,
  sr.Score AS score,
  sr.ViewCount AS viewcount,
  sr.AnswerCount AS answer_count,
  sr.AcceptedAnswerId AS accepted_answer_id,
  sr.tag_score_rank AS tag_rank,
  sr.tag_total_questions AS tag_total_questions,
  sr.tag_avg_score AS tag_avg_score,
  sr.tag_total_upvotes AS tag_total_upvotes,
  sr.post_upvotes AS post_upvotes,
  sr.post_downvotes AS post_downvotes,
  sr.comment_count AS comment_count,
  sr.outbound_duplicate_marks AS outbound_duplicate_marks,
  sr.inbound_duplicate_marks AS inbound_duplicate_marks,
  sr.close_votes_total AS close_events,
  sr.top_commenter_id AS top_commenter_id,
  sr.top_commenter_influence AS top_commenter_influence,
  sr.owner_total_posts AS owner_total_posts,
  sr.gold_badges AS owner_gold_badges,
  sr.silver_badges AS owner_silver_badges,
  sr.bronze_badges AS owner_bronze_badges,
  sr.title_word_count AS title_word_count,
  sr.body_length AS body_length,
  (SELECT EXTRACT(EPOCH FROM (MIN(a.CreationDate) - sr.CreationDate))/86400.0 FROM Posts a WHERE a.ParentId = sr.Id AND a.PostTypeId = 2) AS time_to_first_answer_days,
  (SELECT COUNT(*) FROM Posts a JOIN Users au ON au.Id = a.OwnerUserId WHERE a.ParentId = sr.Id AND a.PostTypeId = 2 AND COALESCE(au.Reputation,0) > COALESCE(sr.owner_reputation,0)) AS answers_by_higher_rep_count,
  (SELECT AVG(COALESCE(a.Score,0)) FROM Posts a WHERE a.ParentId = sr.Id AND a.PostTypeId = 2) AS avg_answer_score,
  sr.computed_metric AS computed_metric,
  ('tag=' || sr.TagName || ', g_rank=' || sr.global_metric_rank || ', t_rank=' || sr.tag_metric_rank) AS note
FROM scored_ranked sr
WHERE sr.global_metric_rank <= 200

UNION ALL

SELECT
  'TAG_SUMMARY'::text AS entity_type,
  NULL::int AS entity_id,
  ta.TagName AS title_or_name,
  ta.TagName AS primary_tag,
  NULL::int AS owner_id,
  NULL::int AS owner_reputation,
  NULL::int AS score,
  COALESCE(ta.tag_avg_views,0)::int AS viewcount,
  ta.tag_question_count::int AS answer_count,
  NULL::int AS accepted_answer_id,
  NULL::int AS tag_rank,
  ta.tag_question_count::int AS tag_total_questions,
  ta.tag_avg_score_of_questions AS tag_avg_score,
  ta.tag_sum_upvotes AS tag_total_upvotes,
  ta.tag_max_upvotes AS post_upvotes,
  ta.tag_sum_comments::int AS post_downvotes,
  NULL::int AS comment_count,
  NULL::int AS outbound_duplicate_marks,
  NULL::int AS inbound_duplicate_marks,
  NULL::int AS close_events,
  NULL::int AS top_commenter_id,
  NULL::int AS top_commenter_influence,
  NULL::int AS owner_total_posts,
  NULL::int AS owner_gold_badges,
  NULL::int AS owner_silver_badges,
  NULL::int AS owner_bronze_badges,
  NULL::int AS title_word_count,
  NULL::int AS body_length,
  NULL::numeric AS time_to_first_answer_days,
  NULL::int AS answers_by_higher_rep_count,
  NULL::numeric AS avg_answer_score,
  ta.tag_sum_upvotes::double precision AS computed_metric,
  'summary' AS note
FROM tag_aggregates ta
ORDER BY computed_metric DESC NULLS LAST, entity_type
LIMIT 500;