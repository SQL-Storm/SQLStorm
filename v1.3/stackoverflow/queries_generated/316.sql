-- {"query": "316.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 16475} 
WITH
raw_posts AS (
  SELECT p.* FROM Posts p
  WHERE p.CreationDate IS NOT NULL
    AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '10 years')
),
questions AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AnswerCount, p.AcceptedAnswerId, p.ClosedDate, p.LastActivityDate
  FROM raw_posts p
  WHERE p.PostTypeId = 1
),
answers AS (
  SELECT p.Id, p.ParentId, p.OwnerUserId, p.CreationDate, p.Score, p.Body, p.CommentCount
  FROM raw_posts p
  WHERE p.PostTypeId = 2
),
votes_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as downvotes,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) as favorites,
         COUNT(*) as total_votes
  FROM Votes v
  WHERE v.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '10 years')
  GROUP BY v.PostId
),
comments_agg AS (
  SELECT c.PostId,
         COUNT(*) as comments_count,
         MAX(c.CreationDate) as last_comment_date,
         MAX(COALESCE(c.Score,0)) as max_comment_score
  FROM Comments c
  GROUP BY c.PostId
),
post_history_agg AS (
  SELECT ph.PostId,
         COUNT(*) as history_count,
         MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) as was_closed,
         MAX(ph.CreationDate) as last_history_date
  FROM PostHistory ph
  GROUP BY ph.PostId
),
tag_exploded AS (
  SELECT q.Id as QuestionId,
         trim(both '<>' from tag) as TagName
  FROM questions q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag
  ) t
),
tag_stats AS (
  SELECT te.TagName,
         COUNT(*) as questions_with_tag,
         AVG(q.Score) as avg_question_score,
         SUM(COALESCE(q.ViewCount,0)) as total_views
  FROM tag_exploded te
  JOIN questions q ON q.Id = te.QuestionId
  GROUP BY te.TagName
),
top_tags AS (
  SELECT TagName, questions_with_tag, avg_question_score, total_views,
         RANK() OVER (ORDER BY questions_with_tag DESC, total_views DESC) as popularity_rank
  FROM tag_stats
),
user_badges AS (
  SELECT b.UserId,
         COUNT(*) as badge_count,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as silver_badges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as bronze_badges,
         COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name ELSE NULL END) as tag_based_badges
  FROM Badges b
  GROUP BY b.UserId
),
answer_stats AS (
  SELECT a.ParentId as QuestionId,
         COUNT(a.Id) as answer_count_calc,
         AVG(a.Score) as avg_answer_score,
         SUM(CASE WHEN a.CreationDate <= q.CreationDate + INTERVAL '7 days' THEN 1 ELSE 0 END) as answers_within_week,
         MAX(a.Score) as max_answer_score
  FROM answers a
  LEFT JOIN questions q ON q.Id = a.ParentId
  GROUP BY a.ParentId, q.CreationDate
),
top_answerers AS (
  SELECT a.OwnerUserId as UserId, te.TagName,
         COUNT(*) as answers_for_tag,
         AVG(a.Score) as avg_score,
         RANK() OVER (PARTITION BY te.TagName ORDER BY COUNT(*) DESC, AVG(a.Score) DESC) as rank_in_tag
  FROM answers a
  JOIN questions q on q.Id = a.ParentId
  JOIN tag_exploded te ON te.QuestionId = q.Id
  WHERE a.OwnerUserId IS NOT NULL
  GROUP BY a.OwnerUserId, te.TagName
),
top_answerer_per_tag AS (
  SELECT TagName, UserId, answers_for_tag, avg_score,
         ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY answers_for_tag DESC, avg_score DESC) as rn
  FROM top_answerers
),
user_activity AS (
  SELECT u.Id as UserId,
         u.DisplayName,
         u.Reputation,
         COALESCE(qcnt.questions_posted,0) as questions_posted,
         COALESCE(acnt.answers_posted,0) as answers_posted,
         COALESCE(accepted.accepted_count,0) as accepted_answers,
         COALESCE(b.badge_count,0) as badge_count,
         COALESCE(b.gold_badges,0) as gold_badges,
         COALESCE(b.silver_badges,0) as silver_badges,
         COALESCE(b.bronze_badges,0) as bronze_badges
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) as questions_posted FROM Posts WHERE PostTypeId = 1 GROUP BY OwnerUserId
  ) qcnt ON qcnt.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) as answers_posted FROM Posts WHERE PostTypeId = 2 GROUP BY OwnerUserId
  ) acnt ON acnt.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT p.OwnerUserId, COUNT(*) as accepted_count
    FROM Posts p
    JOIN Posts q ON q.AcceptedAnswerId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
  ) accepted ON accepted.OwnerUserId = u.Id
  LEFT JOIN user_badges b ON b.UserId = u.Id
),
question_ranking AS (
  SELECT q.Id as QuestionId, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Tags,
         COALESCE(v.upvotes,0) as upvotes,
         COALESCE(v.downvotes,0) as downvotes,
         COALESCE(c.comments_count,0) as comments_count,
         COALESCE(ph.history_count,0) as history_count,
         COALESCE(ans.avg_answer_score,0) as avg_answer_score,
         COALESCE(ans.answer_count_calc,0) as answer_count_calc,
         (CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as has_accepted,
         EXTRACT(epoch FROM (CURRENT_TIMESTAMP - q.CreationDate)) / 86400.0 as age_days,
         ROUND(
           (
             COALESCE(q.Score,0) * 3.0
             + LN(GREATEST(COALESCE(q.ViewCount,0),1) + 1) * 2.0
             + GREATEST(COALESCE(ans.avg_answer_score,0),0) * 4.0
             + COALESCE(v.upvotes,0) * 1.5
             - COALESCE(v.downvotes,0) * 2.0
             + COALESCE(c.comments_count,0) * 0.5
             + COALESCE(ph.history_count,0) * 0.2
             + (CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 50 ELSE 0 END)
           ) / NULLIF(GREATEST(EXTRACT(epoch FROM (CURRENT_TIMESTAMP - q.CreationDate)) / 86400.0, 1.0),0)
           ,4
         ) as quality_score,
         ROW_NUMBER() OVER (ORDER BY 
           (
             COALESCE(q.Score,0) * 3.0
             + LN(GREATEST(COALESCE(q.ViewCount,0),1) + 1) * 2.0
             + GREATEST(COALESCE(ans.avg_answer_score,0),0) * 4.0
             + COALESCE(v.upvotes,0) * 1.5
             - COALESCE(v.downvotes,0) * 2.0
             + COALESCE(c.comments_count,0) * 0.5
             + COALESCE(ph.history_count,0) * 0.2
             + (CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 50 ELSE 0 END)
           ) DESC
         ) as overall_rank
  FROM questions q
  LEFT JOIN votes_agg v ON v.PostId = q.Id
  LEFT JOIN comments_agg c ON c.PostId = q.Id
  LEFT JOIN post_history_agg ph ON ph.PostId = q.Id
  LEFT JOIN answer_stats ans ON ans.QuestionId = q.Id
),
top_question_tags AS (
  SELECT QuestionId, string_agg(TagName, ', ' ORDER BY TagName) as normalized_tags
  FROM (SELECT DISTINCT te.QuestionId, te.TagName FROM tag_exploded te) t
  GROUP BY QuestionId
),
top_answer_for_question AS (
  SELECT qa.QuestionId, qa.AnswerId, qa.AnswererId, qa.AnswerScore
  FROM (
    SELECT a.ParentId as QuestionId, a.Id as AnswerId, a.OwnerUserId as AnswererId, a.Score as AnswerScore,
           ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as rn
    FROM answers a
  ) qa
  WHERE qa.rn = 1
),
accepted_answer_latency AS (
  SELECT q.Id as QuestionId,
         CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN
           EXTRACT(epoch FROM ( (SELECT p.CreationDate FROM Posts p WHERE p.Id = q.AcceptedAnswerId) - q.CreationDate ))/86400.0
         ELSE NULL END as days_to_accept
  FROM questions q
),
suspicious_posts AS (
  SELECT p.Id as PostId, p.PostTypeId, p.Score, COALESCE(v.upvotes,0) as upvotes, COALESCE(v.downvotes,0) as downvotes
  FROM Posts p
  LEFT JOIN votes_agg v ON v.PostId = p.Id
  WHERE COALESCE(v.downvotes,0) > COALESCE(v.upvotes,0) * 3
    AND COALESCE(p.Score,0) < 0
),
duplicate_and_link_info AS (
  SELECT pl.PostId,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) as duplicate_count,
         COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) as linked_out_count
  FROM PostLinks pl
  GROUP BY pl.PostId
),
median_answer_score AS (
  SELECT q.Id as QuestionId,
         (
          SELECT (array_agg(a.Score ORDER BY a.Score))[ceil(count(*)::numeric/2.0)::int]
          FROM answers a WHERE a.ParentId = q.Id
         ) as median_answer_score
  FROM questions q
),
negative_questions AS (
  SELECT q.Id as PostId, q.Title, q.Score, q.ViewCount FROM questions q WHERE q.Score < 0
),
closed_questions AS (
  SELECT DISTINCT ph.PostId as PostId FROM PostHistory ph WHERE ph.PostHistoryTypeId = 10
),
negatives_not_closed AS (
  SELECT * FROM negative_questions
  EXCEPT
  SELECT nq.PostId, nq.Title, nq.Score, nq.ViewCount
  FROM negative_questions nq
  JOIN closed_questions c ON c.PostId = nq.PostId
),
final_assemblage AS (
  SELECT qr.QuestionId, qr.Title, qr.OwnerUserId,
         u.DisplayName as OwnerName, u.Reputation as OwnerReputation,
         COALESCE(v.upvotes,0) as upvotes, COALESCE(v.downvotes,0) as downvotes, COALESCE(v.favorites,0) as favorites,
         COALESCE(qr.quality_score,0) as quality_score,
         COALESCE(ans.max_answer_score,0) as best_answer_score,
         COALESCE(ans.answer_count_calc,0) as total_answers,
         COALESCE(ac.last_comment_date, NULL) as last_comment_date,
         COALESCE(ta.AnswerId, NULL) as top_answer_id, COALESCE(ta.AnswererId, NULL) as top_answerer_id, COALESCE(ua.DisplayName, NULL) as top_answerer_name,
         COALESCE(aal.days_to_accept, NULL) as days_to_accept,
         COALESCE(ds.duplicate_count,0) as duplicate_count,
         COALESCE(ds.linked_out_count,0) as linked_out_count,
         COALESCE(ntc.normalized_tags, '') as tags,
         CASE WHEN EXISTS (SELECT 1 FROM suspicious_posts sp WHERE sp.PostId = qr.QuestionId) THEN true ELSE false END as is_suspicious,
         CASE WHEN qr.CreationDate < CURRENT_TIMESTAMP - INTERVAL '365 days' AND COALESCE(qr.answer_count_calc,0) = 0 THEN 'stale' ELSE 'active' END as lifecycle_status,
         COALESCE(median.median_answer_score, NULL) as median_answer_score,
         COALESCE(ph.was_closed,0) as was_closed,
         qr.overall_rank
  FROM question_ranking qr
  LEFT JOIN Users u ON u.Id = qr.OwnerUserId
  LEFT JOIN votes_agg v ON v.PostId = qr.QuestionId
  LEFT JOIN answer_stats ans ON ans.QuestionId = qr.QuestionId
  LEFT JOIN comments_agg ac ON ac.PostId = qr.QuestionId
  LEFT JOIN top_answer_for_question ta ON ta.QuestionId = qr.QuestionId
  LEFT JOIN Users ua ON ua.Id = ta.AnswererId
  LEFT JOIN accepted_answer_latency aal ON aal.QuestionId = qr.QuestionId
  LEFT JOIN duplicate_and_link_info ds ON ds.PostId = qr.QuestionId
  LEFT JOIN top_question_tags ntc ON ntc.QuestionId = qr.QuestionId
  LEFT JOIN median_answer_score median ON median.QuestionId = qr.QuestionId
  LEFT JOIN post_history_agg ph ON ph.PostId = qr.QuestionId
),
final_selection AS (
  SELECT f.* FROM final_assemblage f
  WHERE f.quality_score IS NOT NULL
  ORDER BY f.quality_score DESC NULLS LAST
  LIMIT 200
)
SELECT *
FROM final_selection;