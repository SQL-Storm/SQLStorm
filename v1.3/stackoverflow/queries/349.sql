-- {"query": "349.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18689} 
WITH
tag_questions AS (
  SELECT q.Id AS question_id,
         q.Title AS title,
         q.CreationDate AS creation_date,
         q.Score AS score,
         q.ViewCount AS view_count,
         q.OwnerUserId AS owner_user_id,
         q.AcceptedAnswerId AS accepted_answer_id,
         q.AnswerCount AS answer_count,
         q.Tags AS tags,
         lower(trim(t.tag)) AS tag
  FROM Posts q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags,2, length(q.Tags)-2), '><')) AS tag
  ) t
  WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL AND q.Tags <> ''
),

global_stats AS (
  SELECT COALESCE(percentile_disc(0.5) WITHIN GROUP (ORDER BY Reputation),0) AS median_reputation,
         COALESCE(AVG(Reputation),0) AS avg_reputation,
         COUNT(*) AS total_users
  FROM Users
),

top_tags AS (
  SELECT tag, COUNT(*) AS question_count
  FROM tag_questions
  GROUP BY tag
  ORDER BY question_count DESC
  LIMIT 20
),

answers_ranked AS (
  SELECT a.Id AS answer_id,
         a.ParentId AS question_id,
         a.CreationDate AS creation_date,
         a.Score AS score,
         a.OwnerUserId AS owner_user_id,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC, a.Id ASC) AS rn,
         RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS rnk,
         COUNT(*) OVER (PARTITION BY a.ParentId) AS answer_count_for_question
  FROM Posts a
  WHERE a.PostTypeId = 2
),

answer_metrics AS (
  SELECT ar.question_id,
         MAX(ar.answer_count_for_question) AS answers_total,
         AVG(ar.score) AS answers_avg_score,
         MAX(ar.score) AS answers_max_score,
         percentile_disc(0.5) WITHIN GROUP (ORDER BY ar.score) AS answers_median_score
  FROM answers_ranked ar
  GROUP BY ar.question_id
),

votes_summary AS (
  SELECT v.PostId AS post_id,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
         SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS bounties_started
  FROM Votes v
  GROUP BY v.PostId
),

duplicate_counts AS (
  SELECT pid AS post_id, COUNT(*) AS duplicate_links
  FROM (
    SELECT PostId AS pid FROM PostLinks WHERE LinkTypeId = 3
    UNION ALL
    SELECT RelatedPostId AS pid FROM PostLinks WHERE LinkTypeId = 3
  ) s
  GROUP BY pid
),

top_by_view AS (
  SELECT Id, Title, ViewCount, Score, CreationDate FROM Posts WHERE PostTypeId = 1 ORDER BY ViewCount DESC LIMIT 200
),
top_by_score AS (
  SELECT Id, Title, ViewCount, Score, CreationDate FROM Posts WHERE PostTypeId = 1 ORDER BY Score DESC LIMIT 200
),
interesting_posts AS (
  SELECT * FROM top_by_view
  UNION
  SELECT * FROM top_by_score
),

top_contributors AS (
  SELECT tq.tag,
         COALESCE(u.Id, -1) AS user_id,
         COALESCE(u.DisplayName, '<anon>') AS display_name,
         COUNT(a.Id) AS answers_for_tag,
         SUM(a.Score) AS answers_score_sum,
         ROW_NUMBER() OVER (PARTITION BY tq.tag ORDER BY COUNT(a.Id) DESC, SUM(a.Score) DESC) AS contributor_rank
  FROM tag_questions tq
  JOIN Posts q ON q.Id = tq.question_id
  JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  GROUP BY tq.tag, COALESCE(u.Id, -1), COALESCE(u.DisplayName, '<anon>')
),

tag_metrics AS (
  SELECT t.tag,
         t.question_count,
         COALESCE(AVG(tq.score),0) AS avg_question_score,
         COALESCE(AVG(tq.view_count),0) AS avg_question_views,
         SUM(CASE WHEN tq.answer_count > 0 THEN 1 ELSE 0 END)::float / NULLIF(t.question_count,0) AS pct_answered,
         AVG(COALESCE(am.answers_total,0)) AS avg_answers_per_question,
         AVG(COALESCE(am.answers_avg_score,0)) AS avg_answer_score_per_question,
         COALESCE( (SELECT STRING_AGG(concat_ws('::', tc.user_id::text, tc.display_name, tc.answers_for_tag::text), ' || ' ORDER BY tc.contributor_rank)
                    FROM top_contributors tc WHERE tc.tag = t.tag AND tc.contributor_rank <= 5), '<none>') AS top_contributors_summary,
         percentile_disc(0.5) WITHIN GROUP (ORDER BY tq.score) AS median_question_score
  FROM top_tags t
  JOIN tag_questions tq ON tq.tag = t.tag
  LEFT JOIN answer_metrics am ON am.question_id = tq.question_id
  GROUP BY t.tag, t.question_count
),

enriched_questions AS (
  SELECT q.question_id,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.OwnerUserId,
         COALESCE(vs.upvotes,0) AS upvotes,
         COALESCE(vs.downvotes,0) AS downvotes,
         COALESCE(dc.duplicate_links,0) AS duplicate_links,
         COALESCE(am.answers_total,0) AS answers_total,
         COALESCE(am.answers_avg_score,0) AS answers_avg_score,
         COALESCE(am.answers_median_score,0) AS answers_median_score,
         COALESCE(ou.Reputation,0) AS owner_reputation,
         CASE WHEN COALESCE(ou.Reputation,0) > gs.median_reputation THEN TRUE ELSE FALSE END AS owner_is_high_rep,
         (LOG(GREATEST(NULLIF(q.ViewCount,0),1)) * (GREATEST(NULLIF(q.Score,0),0) + 1)
            + COALESCE(am.answers_total,0) * 10
            + (COALESCE(vs.upvotes,0) - COALESCE(vs.downvotes,0)) * 2
            - COALESCE(dc.duplicate_links,0) * 5) * EXP(-GREATEST(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - q.CreationDate))/86400.0,1.0)/30.0)
            AS trending_score
  FROM (
    SELECT Id AS question_id, Title, CreationDate, Score, ViewCount, OwnerUserId FROM Posts WHERE PostTypeId = 1
  ) q
  LEFT JOIN votes_summary vs ON vs.post_id = q.question_id
  LEFT JOIN duplicate_counts dc ON dc.post_id = q.question_id
  LEFT JOIN answer_metrics am ON am.question_id = q.question_id
  LEFT JOIN Users ou ON ou.Id = q.OwnerUserId
  CROSS JOIN global_stats gs
),

tag_top_questions AS (
  SELECT tq.tag,
         eq.question_id,
         eq.Title,
         eq.trending_score,
         ROW_NUMBER() OVER (PARTITION BY tq.tag ORDER BY eq.trending_score DESC, eq.answers_total DESC, eq.ViewCount DESC) AS tag_rank
  FROM tag_metrics tm
  JOIN tag_questions tq ON tq.tag = tm.tag
  JOIN enriched_questions eq ON eq.question_id = tq.question_id
)

SELECT
  tm.tag,
  tm.question_count,
  round(tm.avg_question_score::numeric,2) AS avg_question_score,
  round(tm.median_question_score::numeric,2) AS median_question_score,
  round(tm.avg_question_views::numeric,2) AS avg_question_views,
  round(tm.pct_answered::numeric,4) AS pct_answered,
  round(tm.avg_answers_per_question::numeric,2) AS avg_answers_per_question,
  round(tm.avg_answer_score_per_question::numeric,2) AS avg_answer_score_per_question,
  tm.top_contributors_summary,
  COALESCE( (SELECT STRING_AGG(concat_ws('||', tt.question_id::text, tt.Title, round(tt.trending_score::numeric,2)::text), ' || ')
             FROM tag_top_questions tt WHERE tt.tag = tm.tag AND tt.tag_rank <= 3), '<none>') AS top_3_questions,
  (SELECT COUNT(*) FROM interesting_posts ip JOIN tag_questions tq ON tq.question_id = ip.Id WHERE tq.tag = tm.tag) AS interesting_overlap,
  (SELECT AVG(u.Reputation)::int FROM Users u JOIN tag_questions tq2 ON tq2.owner_user_id = u.Id WHERE tq2.tag = tm.tag) AS avg_owner_reputation,
  (SELECT SUM(CASE WHEN COALESCE(dc.duplicate_links,0) > 0 THEN 1 ELSE 0 END)::float / NULLIF(COUNT(*),0)
     FROM tag_questions tq3 LEFT JOIN duplicate_counts dc ON dc.post_id = tq3.question_id
     WHERE tq3.tag = tm.tag) AS pct_questions_with_duplicates
FROM tag_metrics tm
ORDER BY tm.question_count DESC, tm.avg_question_views DESC;