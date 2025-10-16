-- {"query": "229.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6201} 
WITH
recent_questions AS (
  SELECT p.*
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '10 years'
),
exploded_tags AS (
  SELECT q.Id AS QuestionId,
         lower(trim(tag)) AS tag
  FROM recent_questions q
  CROSS JOIN LATERAL (
    SELECT unnest(
      string_to_array(
        substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)
        ), '><'
      )
    ) AS tag
  ) t
  WHERE coalesce(q.Tags,'') <> ''
),
answers_agg AS (
  SELECT ParentId AS QuestionId,
         COUNT(*) AS answers_count,
         MAX(Score) AS max_answer_score,
         AVG(Score)::numeric AS avg_answer_score,
         SUM(CASE WHEN OwnerUserId IS NULL THEN 0 ELSE 1 END) AS answered_by_users
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY ParentId
),
votes_agg AS (
  SELECT v.PostId,
         COUNT(*) AS total_votes,
         SUM((v.VoteTypeId = 2)::int) AS upvotes,
         SUM((v.VoteTypeId = 3)::int) AS downvotes,
         SUM((v.VoteTypeId = 5)::int) AS favorites
  FROM Votes v
  GROUP BY v.PostId
),
links_agg AS (
  SELECT pl.PostId,
         COUNT(*) AS links_out,
         SUM((pl.LinkTypeId = 3)::int) AS duplicates_out
  FROM PostLinks pl
  GROUP BY pl.PostId
),
history_edits AS (
  SELECT ph.PostId,
         COUNT(*) AS edits_total,
         MAX(ph.CreationDate) AS last_edit_date,
         MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.UserId END) AS last_editor_id
  FROM PostHistory ph
  GROUP BY ph.PostId
),
user_badges AS (
  SELECT b.UserId,
         COUNT(*) AS badges_total,
         SUM((b.Class = 1)::int) AS gold,
         SUM((b.Class = 2)::int) AS silver,
         SUM((b.Class = 3)::int) AS bronze,
         MAX(b.Date) AS latest_badge_date,
         MAX(b.Name) AS latest_badge_name
  FROM Badges b
  GROUP BY b.UserId
),
user_activity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         COALESCE(ub.badges_total,0) AS badges_total,
         COALESCE(ub.gold,0) AS gold,
         COALESCE(ub.silver,0) AS silver,
         COALESCE(ub.bronze,0) AS bronze,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rep_rank
  FROM Users u
  LEFT JOIN user_badges ub ON ub.UserId = u.Id
),
accepted_info AS (
  SELECT q.Id AS QuestionId,
         q.AcceptedAnswerId,
         a.Score AS accepted_score,
         a.OwnerUserId AS accepted_owner_id,
         au.DisplayName AS accepted_owner_name
  FROM recent_questions q
  LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
  LEFT JOIN Users au ON au.Id = a.OwnerUserId
),
comments_summary AS (
  SELECT c.PostId,
         COUNT(*) AS comments_count,
         AVG(length(c.Text)) AS avg_comment_len,
         MAX(c.CreationDate) AS last_comment_date,
         substring((array_agg(c.Text ORDER BY c.CreationDate DESC))[1] FROM 1 FOR 120) AS last_comment_excerpt
  FROM Comments c
  GROUP BY c.PostId
),
tag_popularity AS (
  SELECT tag,
         COUNT(DISTINCT QuestionId) AS questions_with_tag,
         RANK() OVER (ORDER BY COUNT(DISTINCT QuestionId) DESC) AS tag_rank
  FROM exploded_tags
  GROUP BY tag
),
controversy_calc AS (
  SELECT q.Id AS QuestionId,
         q.Score,
         COALESCE(va.upvotes,0) AS upvotes,
         COALESCE(va.downvotes,0) AS downvotes,
         COALESCE(q.ViewCount,0) AS views,
         COALESCE(a.answers_count,0) AS answers_count,
         CASE
           WHEN COALESCE(va.upvotes,0)+COALESCE(va.downvotes,0) = 0 THEN 0
           ELSE abs(COALESCE(q.Score,0)) * ln(GREATEST(COALESCE(q.ViewCount,0),1) + 2)
                + sqrt(GREATEST(COALESCE(a.answers_count,0),0))
                + (ln(COALESCE(va.upvotes,0) + 1) - ln(COALESCE(va.downvotes,0) + 1)) * 5
         END AS controversy_score
  FROM recent_questions q
  LEFT JOIN votes_agg va ON va.PostId = q.Id
  LEFT JOIN answers_agg a ON a.QuestionId = q.Id
),
tagged_questions AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.OwnerUserId,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         co.controversy_score,
         ai.AcceptedAnswerId,
         ai.accepted_score,
         ai.accepted_owner_name,
         COALESCE(va.upvotes,0) AS upvotes,
         COALESCE(va.downvotes,0) AS downvotes,
         COALESCE(lk.links_out,0) AS links_out,
         COALESCE(lk.duplicates_out,0) AS duplicates_out,
         COALESCE(h.edits_total,0) AS edits_total,
         COALESCE(cs.comments_count,0) AS comments_count,
         COALESCE(cs.avg_comment_len,0) AS avg_comment_len,
         STRING_AGG(DISTINCT lower(et.tag), '|' ORDER BY lower(et.tag)) AS tags_concat,
         ROW_NUMBER() OVER (ORDER BY co.controversy_score DESC NULLS LAST) AS overall_controversy_rank
  FROM recent_questions q
  LEFT JOIN exploded_tags et ON et.QuestionId = q.Id
  LEFT JOIN votes_agg va ON va.PostId = q.Id
  LEFT JOIN links_agg lk ON lk.PostId = q.Id
  LEFT JOIN history_edits h ON h.PostId = q.Id
  LEFT JOIN comments_summary cs ON cs.PostId = q.Id
  LEFT JOIN accepted_info ai ON ai.QuestionId = q.Id
  LEFT JOIN controversy_calc co ON co.QuestionId = q.Id
  GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount,
           co.controversy_score, ai.AcceptedAnswerId, ai.accepted_score, ai.accepted_owner_name,
           va.upvotes, va.downvotes, lk.links_out, lk.duplicates_out, h.edits_total, cs.comments_count, cs.avg_comment_len
),
tag_question_ranks AS (
  SELECT lower(et.tag) AS tag,
         tq.QuestionId,
         ROW_NUMBER() OVER (PARTITION BY lower(et.tag) ORDER BY tq.controversy_score DESC NULLS LAST) AS tag_rank_in_group
  FROM exploded_tags et
  JOIN tagged_questions tq ON tq.QuestionId = et.QuestionId
),
tag_rank_agg AS (
  SELECT QuestionId,
         MIN(tag_rank_in_group) AS best_tag_rank
  FROM tag_question_ranks
  GROUP BY QuestionId
),
top_by_controversy AS (
  SELECT tq.*,
         ua.DisplayName AS owner_name,
         ua.Reputation AS owner_reputation,
         ua.badges_total AS owner_badges,
         COALESCE(tr.best_tag_rank, 9999) AS best_tag_rank
  FROM tagged_questions tq
  LEFT JOIN user_activity ua ON ua.UserId = tq.OwnerUserId
  LEFT JOIN tag_rank_agg tr ON tr.QuestionId = tq.QuestionId
  WHERE tq.overall_controversy_rank <= 100
  ORDER BY tq.controversy_score DESC NULLS LAST
  LIMIT 100
),
top_by_views AS (
  SELECT tq.*,
         ua.DisplayName AS owner_name,
         ua.Reputation AS owner_reputation,
         ua.badges_total AS owner_badges,
         COALESCE(tr.best_tag_rank, 9999) AS best_tag_rank
  FROM tagged_questions tq
  LEFT JOIN user_activity ua ON ua.UserId = tq.OwnerUserId
  LEFT JOIN tag_rank_agg tr ON tr.QuestionId = tq.QuestionId
  ORDER BY tq.ViewCount DESC NULLS LAST
  LIMIT 100
),
unioned AS (
  SELECT 'controversy' AS selector, *
  FROM top_by_controversy
  UNION
  SELECT 'views' AS selector, *
  FROM top_by_views
),
final_ranked AS (
  SELECT u.*,
         ROW_NUMBER() OVER (PARTITION BY selector ORDER BY controversy_score DESC NULLS LAST, ViewCount DESC NULLS LAST) AS rank_within_set,
         DENSE_RANK() OVER (ORDER BY owner_reputation DESC NULLS LAST) AS owner_reputation_rank
  FROM unioned u
)
SELECT selector,
       QuestionId,
       COALESCE(Title, '') AS Title,
       owner_name,
       owner_reputation,
       owner_badges,
       Score,
       ViewCount,
       AnswerCount,
       upvotes,
       downvotes,
       ROUND(controversy_score::numeric,6) AS controversy_score,
       COALESCE(tags_concat, '') AS tags_concat,
       comments_count,
       ROUND(COALESCE(avg_comment_len,0)::numeric,2) AS avg_comment_len,
       edits_total,
       links_out,
       duplicates_out,
       AcceptedAnswerId,
       accepted_score,
       accepted_owner_name,
       rank_within_set,
       owner_reputation_rank,
       CASE
         WHEN accepted_score IS NULL AND COALESCE(Score,0) < 0 THEN 'neg_unanswered'
         WHEN accepted_score IS NOT NULL AND accepted_score > COALESCE(Score,0) THEN 'accepted_better'
         WHEN COALESCE(upvotes,0) = 0 AND COALESCE(downvotes,0) = 0 AND comments_count > 0 THEN 'discussed_no_votes'
         ELSE 'other'
       END AS status_category,
       (CASE WHEN avg_comment_len IS NULL THEN 0 ELSE avg_comment_len END) /
         NULLIF(NULLIF(AnswerCount,0),0) AS comment_len_per_answer,
       md5(COALESCE(Title,'') || '|' || COALESCE(tags_concat,'')) AS signature_hash,
       -- correlated existence checks
       EXISTS (
         SELECT 1 FROM PostLinks pl WHERE pl.PostId = QuestionId AND pl.LinkTypeId = 3
       ) AS has_duplicate_link,
       EXISTS (
         SELECT 1 FROM PostHistory ph WHERE ph.PostId = QuestionId AND ph.PostHistoryTypeId = 10
       ) AS ever_closed
FROM final_ranked
ORDER BY selector, rank_within_set, controversy_score DESC NULLS LAST
LIMIT 200;