-- {"query": "347.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14109} 
WITH
q_posts AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
),
a_posts AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 2
),
tag_exploded AS (
  SELECT p.Id AS QuestionId,
         lower(trim(s.t)) AS tag
  FROM q_posts p
  CROSS JOIN LATERAL regexp_split_to_table(
       coalesce(substring(p.Tags, 2, greatest(length(coalesce(p.Tags,'')) - 2, 0)), '')
  ) AS s(t)
  WHERE coalesce(s.t,'') <> ''
),
votes_summary AS (
  SELECT PostId,
         sum(case when VoteTypeId = 2 then 1 else 0 end) as upvotes,
         sum(case when VoteTypeId = 3 then 1 else 0 end) as downvotes,
         sum(case when VoteTypeId = 5 then 1 else 0 end) as favors,
         sum(case when VoteTypeId in (8,9) then coalesce(BountyAmount,0) else 0 end) as bounty_total,
         count(*) as votes_total,
         max(case when VoteTypeId in (8,9) then CreationDate end) as last_bounty_date
  FROM Votes
  GROUP BY PostId
),
post_history_agg AS (
  SELECT PostId,
         count(*) FILTER (WHERE PostHistoryTypeId = 5) as body_edits,
         count(*) FILTER (WHERE PostHistoryTypeId = 4) as title_edits,
         count(*) FILTER (WHERE PostHistoryTypeId in (10,11)) as close_reopen_events,
         max(CreationDate) as last_history_date
  FROM PostHistory
  GROUP BY PostId
),
answer_stats AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.OwnerUserId,
         a.Score,
         coalesce(vs.upvotes,0) AS upvotes,
         coalesce(vs.downvotes,0) AS downvotes,
         coalesce(vs.favors,0) as favors,
         coalesce(vs.bounty_total,0) as bounty_total,
         extract(epoch from (a.CreationDate - q.CreationDate))/60.0 as answer_minutes_after_question,
         row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, coalesce(vs.upvotes,0) DESC, a.CreationDate) as answer_rank_by_score,
         rank() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as rnk,
         case when q.AcceptedAnswerId = a.Id then true else false end as is_accepted
  FROM a_posts a
  LEFT JOIN q_posts q ON q.Id = a.ParentId
  LEFT JOIN votes_summary vs ON vs.PostId = a.Id
),
user_qa_agg AS (
  SELECT u.Id as UserId,
         u.DisplayName,
         count(distinct q.Id) FILTER (WHERE q.OwnerUserId = u.Id) as questions_asked,
         count(distinct a.AnswerId) FILTER (WHERE a.OwnerUserId = u.Id) as answers_posted,
         sum(a.Score) FILTER (WHERE a.OwnerUserId = u.Id) as total_answer_score,
         sum(case when a.is_accepted then 1 else 0 end) FILTER (WHERE a.OwnerUserId = u.Id) as accepted_answers,
         coalesce(sum(a.upvotes) FILTER (WHERE a.OwnerUserId = u.Id),0) as answer_upvotes,
         u.Reputation,
         u.CreationDate as user_created
  FROM Users u
  LEFT JOIN q_posts q ON q.OwnerUserId = u.Id
  LEFT JOIN answer_stats a ON a.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
top_tag_questions AS (
  SELECT te.tag,
         q.Id as QuestionId,
         q.Title,
         q.OwnerUserId,
         q.Score,
         q.ViewCount,
         coalesce(vs.upvotes,0) as upvotes,
         coalesce(ph.body_edits,0) as body_edits,
         (q.ViewCount::numeric * 0.1 + q.Score * 5 + coalesce(vs.upvotes,0) * 2 + coalesce(q.FavoriteCount,0) * 3 - coalesce(ph.body_edits,0) * 1) as hotness_score
  FROM tag_exploded te
  JOIN q_posts q ON q.Id = te.QuestionId
  LEFT JOIN votes_summary vs ON vs.PostId = q.Id
  LEFT JOIN post_history_agg ph ON ph.PostId = q.Id
  WHERE q.ClosedDate IS NULL OR q.ClosedDate > current_timestamp - interval '365 days'
),
ranked_tags_questions AS (
  SELECT *,
         row_number() OVER (PARTITION BY tag ORDER BY hotness_score DESC, upvotes DESC, Score DESC) as tag_q_rank
  FROM top_tag_questions
),
answers_with_tags AS (
  SELECT te.tag,
         a.AnswerId,
         a.QuestionId,
         a.OwnerUserId,
         a.Score,
         a.upvotes,
         a.downvotes,
         a.is_accepted,
         coalesce(vs.bounty_total,0) as bounty_on_answer
  FROM tag_exploded te
  JOIN answer_stats a ON a.QuestionId = te.QuestionId
  LEFT JOIN votes_summary vs ON vs.PostId = a.AnswerId
),
tag_user_scores AS (
  SELECT tag,
         OwnerUserId as UserId,
         sum( (coalesce(Score,0) * 3) + (coalesce(upvotes,0) * 2) + (case when is_accepted then 50 else 0 end) + coalesce(bounty_on_answer,0) ) as tag_score,
         count(*) as answers_count
  FROM answers_with_tags
  GROUP BY tag, OwnerUserId
),
top_users_per_tag AS (
  SELECT tag, UserId, tag_score, answers_count,
         row_number() OVER (PARTITION BY tag ORDER BY tag_score DESC, answers_count DESC) as user_rank
  FROM tag_user_scores
),
high_rep AS (
  SELECT Id as UserId FROM Users WHERE Reputation >= 20000
),
badged_modern AS (
  SELECT distinct UserId FROM Badges WHERE UserId IS NOT NULL
),
prominent_users AS (
  SELECT UserId FROM high_rep
  INTERSECT
  SELECT UserId FROM badged_modern
),
final_tag_summary AS (
  SELECT t.tag,
         (SELECT string_agg(concat('Q[', rq.QuestionId, ']:', left(coalesce(rq.Title,''),60), ' (hot=', round(rq.hotness_score::numeric,2), ')'), ' || ')
          FROM ranked_tags_questions rq WHERE rq.tag = t.tag AND rq.tag_q_rank <= 3
         ) as top_questions,
         (SELECT string_agg(concat('U[', tp.UserId, ']:', coalesce(u.DisplayName,'<anon>'), ' (score=', tp.tag_score, ',ans=', tp.answers_count,')'), ' || ')
          FROM top_users_per_tag tp
          LEFT JOIN Users u ON u.Id = tp.UserId
          WHERE tp.tag = t.tag AND tp.user_rank <= 3
         ) as top_users,
         (SELECT count(distinct q2.Id) FROM q_posts q2 WHERE EXISTS (SELECT 1 FROM tag_exploded te2 WHERE te2.QuestionId = q2.Id AND te2.tag = t.tag)) as questions_with_tag,
         (SELECT avg(q3.Score::numeric) FROM q_posts q3 WHERE EXISTS (SELECT 1 FROM tag_exploded te3 WHERE te3.QuestionId = q3.Id AND te3.tag = t.tag)) as avg_question_score,
         (SELECT max(q4.ViewCount) FROM q_posts q4 WHERE EXISTS (SELECT 1 FROM tag_exploded te4 WHERE te4.QuestionId = q4.Id AND te4.tag = t.tag)) as max_views,
         (SELECT min(q5.ViewCount) FROM q_posts q5 WHERE EXISTS (SELECT 1 FROM tag_exploded te5 WHERE te5.QuestionId = q5.Id AND te5.tag = t.tag)) as min_views
  FROM (SELECT distinct tag FROM tag_exploded) t
),
median_answer_time AS (
  SELECT tag,
         (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (a2.CreationDate - q.CreationDate))/60.0)
          FROM Posts a2
          JOIN Posts q ON q.Id = a2.ParentId
          WHERE a2.PostTypeId = 2
            AND q.PostTypeId = 1
            AND EXISTS (SELECT 1 FROM tag_exploded te2 WHERE te2.QuestionId = q.Id AND te2.tag = t.tag)
         ) as median_answer_minutes
  FROM (SELECT distinct tag FROM tag_exploded) t
),
duplicate_chain AS (
  SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId,
         p1.Title as FromTitle,
         p2.Title as ToTitle,
         concat(coalesce(left(p1.Title,50),''), ' -> ', coalesce(left(p2.Title,50),'')) as short_chain,
         row_number() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) as chain_rank
  FROM PostLinks pl
  LEFT JOIN Posts p1 ON p1.Id = pl.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE pl.LinkTypeId = 3
),
outer_aggregated AS (
  SELECT f.tag,
         f.top_questions,
         f.top_users,
         f.questions_with_tag,
         f.avg_question_score,
         f.max_views,
         f.min_views,
         coalesce(m.median_answer_minutes, -1) as median_answer_minutes,
         count(distinct dc.PostId) FILTER (WHERE dc.chain_rank = 1) as duplicate_count_sample,
         (SELECT count(*) FROM prominent_users pu WHERE exists (
            SELECT 1 FROM tag_user_scores tus WHERE tus.tag = f.tag AND tus.UserId = pu.UserId
         )) as prominent_users_in_tag,
         replace(upper(f.tag), '-', '_') as tag_normalized
  FROM final_tag_summary f
  LEFT JOIN median_answer_time m ON m.tag = f.tag
  LEFT JOIN duplicate_chain dc ON dc.chain_rank = 1 AND EXISTS (
     SELECT 1 FROM tag_exploded te WHERE te.QuestionId = dc.PostId AND te.tag = f.tag
  )
  GROUP BY f.tag, f.top_questions, f.top_users, f.questions_with_tag, f.avg_question_score, f.max_views, f.min_views, m.median_answer_minutes
)

SELECT o.tag,
       o.tag_normalized,
       o.questions_with_tag,
       round(o.avg_question_score::numeric,2) as avg_question_score,
       o.max_views,
       o.min_views,
       round(o.median_answer_minutes::numeric,2) as median_answer_minutes,
       o.duplicate_count_sample,
       o.prominent_users_in_tag,
       o.top_questions,
       o.top_users
FROM outer_aggregated o
WHERE o.questions_with_tag > 5
  AND (o.avg_question_score IS NULL OR o.avg_question_score > 0 OR o.median_answer_minutes < 10000)
ORDER BY o.prominent_users_in_tag DESC NULLS LAST, o.questions_with_tag DESC, o.avg_question_score DESC
LIMIT 250;