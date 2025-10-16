-- {"query": "320.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17004} 
WITH
recent_questions AS (
  SELECT p.*,
         COALESCE(p.Tags,'') AS tags_raw,
         substring(COALESCE(p.Tags,''), 2, GREATEST(length(COALESCE(p.Tags,'')) - 2, 0)) AS tags_inner
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '3 years'
),
q_tags AS (
  SELECT rq.Id AS QuestionId,
         unnest(string_to_array(rq.tags_inner, '><')) AS tag
  FROM recent_questions rq
  WHERE rq.tags_inner <> ''
),
tags_per_q AS (
  SELECT QuestionId,
         string_agg(tag, ',' ORDER BY tag) AS tags_list,
         COUNT(*) AS tag_count
  FROM q_tags
  GROUP BY QuestionId
),
votes_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS vote_net_score,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         COUNT(*) AS votes_total
  FROM Votes v
  GROUP BY v.PostId
),
answers_agg AS (
  SELECT a.ParentId AS QuestionId,
         COUNT(*) AS answers_total,
         SUM(COALESCE(a.Score,0)) AS answers_score_sum,
         MAX(a.Score) AS top_answer_score,
         AVG(COALESCE(a.Score,0)) AS answers_score_avg,
         SUM(CASE WHEN a.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS anon_answers
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
comments_agg AS (
  SELECT c.PostId,
         COUNT(*) AS comment_count,
         MAX(c.CreationDate) AS last_comment_date,
         SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS anonymous_comments
  FROM Comments c
  GROUP BY c.PostId
),
links_agg AS (
  SELECT pl.PostId,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicates_out,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS links_out,
         COUNT(*) AS links_total
  FROM PostLinks pl
  GROUP BY pl.PostId
),
badges_agg AS (
  SELECT b.UserId,
         COUNT(*) AS badges_total,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
  FROM Badges b
  GROUP BY b.UserId
),
user_post_stats AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         COALESCE(u.DisplayName,'(anonymous)') AS display_name,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_posted,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_posted,
         AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS avg_post_score,
         COUNT(q.Id) FILTER (WHERE q.Id IS NOT NULL) AS accepted_answers_count,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rep_rank
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts q ON q.AcceptedAnswerId = p.Id AND p.PostTypeId = 2
  GROUP BY u.Id, u.Reputation, u.DisplayName
),
question_quality AS (
  SELECT rq.Id AS QuestionId,
         rq.Title,
         rq.OwnerUserId,
         rq.CreationDate,
         COALESCE(v.vote_net_score,0) AS q_vote_net,
         COALESCE(a.answers_total,0) AS answers_total,
         COALESCE(a.answers_score_avg,0) AS answers_avg_score,
         COALESCE(a.top_answer_score,0) AS top_answer_score,
         COALESCE(c.comment_count,0) AS comment_count,
         COALESCE(l.duplicates_out,0) AS duplicates_out,
         COALESCE(b.gold_badges,0) AS owner_gold_badges,
         COALESCE(b.silver_badges,0) AS owner_silver_badges,
         (SELECT COUNT(DISTINCT v2.UserId)
          FROM Votes v2
          LEFT JOIN Posts p2 ON p2.Id = v2.PostId
          WHERE (v2.PostId = rq.Id OR (p2.ParentId = rq.Id AND p2.PostTypeId = 2))
            AND v2.UserId IS NOT NULL
            AND v2.CreationDate >= rq.CreationDate
            AND v2.CreationDate < rq.CreationDate + interval '7 days'
         ) AS distinct_voters_week,
         (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rq.Id AND ph.PostHistoryTypeId IN (10,11,12,13,35) AND ph.CreationDate >= rq.CreationDate - interval '30 days') AS history_incidents,
         EXTRACT(EPOCH FROM (now() - rq.CreationDate))/86400.0 AS age_days,
         CASE WHEN COALESCE(v.vote_net_score,0)=0 THEN NULL
              ELSE ((COALESCE(a.answers_score_avg,0) + COALESCE(v.vote_net_score,0)) / NULLIF(EXTRACT(EPOCH FROM (now() - rq.CreationDate))/86400.0,0))
         END AS quality_density
  FROM recent_questions rq
  LEFT JOIN votes_agg v ON v.PostId = rq.Id
  LEFT JOIN answers_agg a ON a.QuestionId = rq.Id
  LEFT JOIN comments_agg c ON c.PostId = rq.Id
  LEFT JOIN links_agg l ON l.PostId = rq.Id
  LEFT JOIN badges_agg b ON b.UserId = rq.OwnerUserId
),
ranked_questions AS (
  SELECT qq.*,
         (COALESCE(qq.q_vote_net,0) * 1.5
          + COALESCE(qq.answers_total,0) * 2.2
          + COALESCE(qq.answers_avg_score,0) * 1.8
          + COALESCE(qq.comment_count,0) * 0.5
          + COALESCE(qq.owner_gold_badges,0) * 3
          - COALESCE(qq.duplicates_out,0) * 5
          + COALESCE(qq.distinct_voters_week,0) * 1.0
          - COALESCE(qq.history_incidents,0) * 2.5
          + COALESCE(qq.quality_density,0) * 10
         ) AS composite_score,
         RANK() OVER (ORDER BY (COALESCE(qq.q_vote_net,0) * 1.5
          + COALESCE(qq.answers_total,0) * 2.2
          + COALESCE(qq.answers_avg_score,0) * 1.8
          + COALESCE(qq.comment_count,0) * 0.5
          + COALESCE(qq.owner_gold_badges,0) * 3
          - COALESCE(qq.duplicates_out,0) * 5
          + COALESCE(qq.distinct_voters_week,0) * 1.0
          - COALESCE(qq.history_incidents,0) * 2.5
          + COALESCE(qq.quality_density,0) * 10
         ) DESC NULLS LAST) AS composite_rank
  FROM question_quality qq
),
top_by_composite AS (
  SELECT QuestionId, composite_score, composite_rank FROM ranked_questions WHERE composite_rank <= 100
),
top_by_votes AS (
  SELECT v.PostId AS QuestionId, v.vote_net_score::numeric AS composite_score, NULL::bigint AS composite_rank
  FROM votes_agg v
  JOIN Posts p ON p.Id = v.PostId
  WHERE p.PostTypeId = 1
  ORDER BY v.vote_net_score DESC NULLS LAST
  LIMIT 100
),
top_union AS (
  SELECT * FROM top_by_composite
  UNION
  SELECT * FROM top_by_votes
),
top_questions AS (
  SELECT t.QuestionId
  FROM (SELECT DISTINCT QuestionId FROM top_union) t
  LEFT JOIN ranked_questions r ON r.QuestionId = t.QuestionId
  ORDER BY COALESCE(r.composite_score,0) DESC NULLS LAST
  LIMIT 50
),
controversial_by_votes AS (
  SELECT PostId FROM votes_agg WHERE upvotes >= 10 AND downvotes >= 10
),
controversial_by_history AS (
  SELECT PostId FROM PostHistory WHERE PostHistoryTypeId IN (10,12,35) GROUP BY PostId HAVING COUNT(*) >= 5
),
controversial_intersection AS (
  SELECT * FROM controversial_by_votes
  INTERSECT
  SELECT * FROM controversial_by_history
),
controversial_only_votes AS (
  SELECT * FROM controversial_by_votes
  EXCEPT
  SELECT * FROM controversial_by_history
)
SELECT
  rq.Id AS question_id,
  LEFT(REPLACE(COALESCE(rq.Title,'[no title]'), E'\n',' '), 200) AS title_snip,
  COALESCE(tp.tags_list, '(none)') AS tags,
  COALESCE(tp.tag_count, 0) AS tag_count,
  COALESCE(v.vote_net_score,0) AS question_vote_net,
  COALESCE(a.answers_total,0) AS answers_total,
  ROUND(COALESCE(a.answers_score_avg,0)::numeric,4) AS answers_avg_score,
  COALESCE(a.top_answer_score,0) AS top_answer_score,
  COALESCE(c.comment_count,0) AS comments,
  COALESCE(l.links_total,0) AS links_total,
  COALESCE(l.duplicates_out,0) AS duplicates,
  COALESCE(b_own.badges_total,0) AS owner_badges_total,
  COALESCE(u.Reputation,0) AS owner_reputation,
  COALESCE(u.DisplayName, rq.OwnerDisplayName, '(unknown)') AS owner_display_name,
  rq.AcceptedAnswerId,
  COALESCE(rq.FavoriteCount,0) AS favorite_count,
  CASE WHEN rq.Body ~ '<code>' THEN true ELSE false END AS body_contains_code,
  (SELECT EXTRACT(EPOCH FROM (MIN(a2.CreationDate) - rq.CreationDate))/3600.0
   FROM Posts a2
   WHERE a2.ParentId = rq.Id AND a2.PostTypeId = 2
  ) AS hours_to_first_answer,
  (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY a3.Score)
   FROM Posts a3
   WHERE a3.ParentId = rq.Id AND a3.PostTypeId = 2
  ) AS median_answer_score,
  (SELECT COUNT(DISTINCT a4.OwnerUserId) FROM Posts a4 WHERE a4.ParentId = rq.Id AND a4.PostTypeId = 2 AND a4.OwnerUserId IS NOT NULL) AS answerers_unique_count,
  (ABS(COALESCE(v.vote_net_score,0))
   + COALESCE((SELECT SUM(ABS(v2.vote_net_score))
               FROM votes_agg v2
               JOIN Posts p2 ON p2.Id = v2.PostId
               WHERE p2.ParentId = rq.Id
              ),0)
  ) / NULLIF(GREATEST(1, COALESCE(a.answers_total,0)),1) AS controversy_index,
  ans.top_answers_json,
  r.composite_score,
  r.composite_rank,
  CASE WHEN rq.Id IN (SELECT PostId FROM controversial_intersection) THEN 'intersection'
       WHEN rq.Id IN (SELECT PostId FROM controversial_only_votes) THEN 'only_votes'
       WHEN rq.Id IN (SELECT PostId FROM controversial_by_history) THEN 'only_history'
       ELSE 'none' END AS controversy_flag
FROM Posts rq
JOIN top_questions tq ON tq.QuestionId = rq.Id
LEFT JOIN tags_per_q tp ON tp.QuestionId = rq.Id
LEFT JOIN votes_agg v ON v.PostId = rq.Id
LEFT JOIN answers_agg a ON a.QuestionId = rq.Id
LEFT JOIN comments_agg c ON c.PostId = rq.Id
LEFT JOIN links_agg l ON l.PostId = rq.Id
LEFT JOIN badges_agg b_own ON b_own.UserId = rq.OwnerUserId
LEFT JOIN Users u ON u.Id = rq.OwnerUserId
LEFT JOIN ranked_questions r ON r.QuestionId = rq.Id
LEFT JOIN LATERAL (
  SELECT json_agg(json_build_object(
           'AnswerId', a2.Id,
           'Score', a2.Score,
           'OwnerUserId', a2.OwnerUserId,
           'OwnerDisplayName', COALESCE(a2.OwnerDisplayName, u2.DisplayName, '(anonymous)'),
           'Comments', COALESCE(ca.cnt,0),
           'IsAccepted', CASE WHEN a2.Id = rq.AcceptedAnswerId THEN true ELSE false END
         ) ORDER BY a2.Score DESC) FILTER (WHERE a2.Id IS NOT NULL) AS top_answers_json
  FROM (
     SELECT * FROM Posts WHERE ParentId = rq.Id AND PostTypeId = 2 ORDER BY Score DESC NULLS LAST LIMIT 3
  ) a2
  LEFT JOIN Users u2 ON u2.Id = a2.OwnerUserId
  LEFT JOIN (SELECT PostId, COUNT(*) cnt FROM Comments GROUP BY PostId) ca ON ca.PostId = a2.Id
) ans ON true
ORDER BY r.composite_rank ASC NULLS LAST, r.composite_score DESC NULLS LAST
LIMIT 50;