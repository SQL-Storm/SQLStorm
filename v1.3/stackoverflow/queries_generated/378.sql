-- {"query": "378.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17042} 
WITH
tagged_questions AS (
  SELECT p.Id AS question_id,
         p.Title,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.FavoriteCount,
         lower(trim(t.tag)) AS tag
  FROM Posts p
  CROSS JOIN LATERAL unnest(
    string_to_array(
      CASE WHEN p.Tags IS NULL OR char_length(p.Tags) < 3 THEN '' ELSE substring(p.Tags FROM 2 FOR char_length(p.Tags)-2) END
    , '><')
  ) AS t(tag)
  WHERE p.PostTypeId = 1
    AND COALESCE(p.Tags,'') <> ''
    AND t.tag IS NOT NULL
    AND t.tag <> ''
),

answers_agg AS (
  SELECT a.ParentId AS question_id,
         COUNT(*) AS total_answers,
         SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS positive_answers,
         AVG(a.Score) AS avg_answer_score,
         MAX(a.Score) AS max_answer_score,
         COUNT(DISTINCT a.OwnerUserId) AS distinct_answerers
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),

comment_stats AS (
  SELECT c.PostId AS post_id,
         COUNT(*) AS comment_count,
         MAX(c.CreationDate) AS last_comment_date,
         MAX(c.Id) FILTER (WHERE c.Score = (SELECT COALESCE(MAX(c2.Score), -2147483648) FROM Comments c2 WHERE c2.PostId = c.PostId)) AS top_comment_id
  FROM Comments c
  GROUP BY c.PostId
),

vote_stats AS (
  SELECT v.PostId AS post_id,
         COUNT(*) AS total_votes,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites,
         SUM(COALESCE(v.BountyAmount,0)) AS total_bounty,
         MAX(v.CreationDate) AS last_vote_date
  FROM Votes v
  GROUP BY v.PostId
),

badges_per_user AS (
  SELECT b.UserId,
         COUNT(*) AS badges_total,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
         SUM(CASE WHEN b.TagBased = B'1' THEN 1 ELSE 0 END) AS tag_based
  FROM Badges b
  GROUP BY b.UserId
),

user_post_times AS (
  SELECT p.OwnerUserId AS user_id,
         p.Id AS post_id,
         p.CreationDate,
         p.PostTypeId,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS rn,
         LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_creation
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),

user_post_gaps AS (
  SELECT user_id,
         AVG(EXTRACT(EPOCH FROM (CreationDate - prev_creation))) AS avg_seconds_between_posts,
         COUNT(*) AS gaps_count
  FROM user_post_times
  WHERE prev_creation IS NOT NULL
  GROUP BY user_id
),

user_posts AS (
  SELECT p.OwnerUserId AS user_id,
         COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
         COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
         AVG(COALESCE(p.Score,0)) AS avg_post_score,
         SUM(COALESCE(p.ViewCount,0)) AS total_views,
         MAX(p.Score) AS best_post_score
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),

tag_stats AS (
  SELECT tq.tag,
         COUNT(*) AS question_count,
         SUM(COALESCE(tq.ViewCount,0)) AS total_views,
         AVG(COALESCE(tq.Score,0)) AS avg_score,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY COALESCE(tq.Score,0)) AS median_score,
         MAX(tq.Score) AS max_score,
         MIN(tq.CreationDate) AS first_question,
         MAX(tq.CreationDate) AS last_question
  FROM tagged_questions tq
  GROUP BY tq.tag
),

tag_contributors AS (
  SELECT tq.tag,
         a.OwnerUserId AS user_id,
         COUNT(*) AS answers_count,
         SUM(COALESCE(a.Score,0)) AS answer_score_sum,
         AVG(COALESCE(a.Score,0)) AS answer_score_avg
  FROM tagged_questions tq
  JOIN Posts a ON a.ParentId = tq.question_id AND a.PostTypeId = 2
  GROUP BY tq.tag, a.OwnerUserId
),

tag_top_contributors AS (
  SELECT tc.*,
         ROW_NUMBER() OVER (PARTITION BY tc.tag ORDER BY tc.answer_score_sum DESC NULLS LAST, tc.answers_count DESC NULLS LAST) AS rn
  FROM tag_contributors tc
),

tag_top_contributor_one AS (
  SELECT tag, user_id, answers_count, answer_score_sum, answer_score_avg
  FROM tag_top_contributors
  WHERE rn = 1
),

link_stats AS (
  SELECT pl.PostId AS question_id,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS outgoing_duplicates,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS outgoing_links,
         COUNT(*) AS total_links
  FROM PostLinks pl
  GROUP BY pl.PostId
),

link_incoming AS (
  SELECT pl.RelatedPostId AS question_id,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS incoming_duplicates,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS incoming_links,
         COUNT(*) AS total_incoming
  FROM PostLinks pl
  GROUP BY pl.RelatedPostId
),

tag_link_stats AS (
  SELECT tq.tag,
         SUM(COALESCE(ls.outgoing_duplicates,0)) AS sum_outgoing_duplicates,
         SUM(COALESCE(ls.outgoing_links,0)) AS sum_outgoing_links,
         SUM(COALESCE(ls.total_links,0)) AS sum_total_links,
         SUM(COALESCE(li.incoming_duplicates,0)) AS sum_incoming_duplicates,
         SUM(COALESCE(li.incoming_links,0)) AS sum_incoming_links,
         SUM(COALESCE(li.total_incoming,0)) AS sum_total_incoming
  FROM tagged_questions tq
  LEFT JOIN link_stats ls ON ls.question_id = tq.question_id
  LEFT JOIN link_incoming li ON li.question_id = tq.question_id
  GROUP BY tq.tag
),

tag_answer_stats AS (
  SELECT tq.tag,
         SUM(COALESCE(aa.total_answers,0)) AS sum_answers,
         AVG(aa.avg_answer_score) AS avg_answer_score,
         MAX(aa.max_answer_score) AS max_answer_score,
         SUM(COALESCE(aa.distinct_answerers,0)) AS distinct_answerers
  FROM tagged_questions tq
  LEFT JOIN answers_agg aa ON aa.question_id = tq.question_id
  GROUP BY tq.tag
),

edit_activity AS (
  SELECT ph.PostId AS post_id,
         COUNT(*) AS revisions,
         MAX(ph.CreationDate) AS last_edit,
         bool_or(ph.PostHistoryTypeId IN (4,5,6,24)) AS has_content_edits
  FROM PostHistory ph
  GROUP BY ph.PostId
),

hot_by_views AS (
  SELECT p.Id AS question_id
  FROM Posts p
  WHERE p.PostTypeId = 1 AND COALESCE(p.ViewCount,0) > 10000
),

hot_by_score AS (
  SELECT p.Id AS question_id
  FROM Posts p
  WHERE p.PostTypeId = 1 AND COALESCE(p.Score,0) > 50
),

hot_questions AS (
  (SELECT question_id FROM hot_by_views)
  UNION
  (SELECT question_id FROM hot_by_score)
  EXCEPT
  (SELECT Id FROM Posts WHERE PostTypeId = 1 AND ClosedDate IS NOT NULL)
),

hot_tag_counts AS (
  SELECT tq.tag,
         COUNT(DISTINCT hq.question_id) AS hot_questions
  FROM tagged_questions tq
  JOIN hot_questions hq ON hq.question_id = tq.question_id
  GROUP BY tq.tag
),

top_tags_by_views AS (
  SELECT tag FROM tag_stats ORDER BY total_views DESC NULLS LAST LIMIT 200
),

tags_by_reputable_top AS (
  SELECT t.tag FROM tag_top_contributor_one t JOIN Users u ON u.Id = t.user_id WHERE COALESCE(u.Reputation,0) > 5000
),

hot_and_reputable_tags AS (
  (SELECT tag FROM top_tags_by_views)
  INTERSECT
  (SELECT tag FROM tags_by_reputable_top)
),

final_tag_metrics AS (
  SELECT ts.tag,
         ts.question_count,
         ts.total_views,
         ts.avg_score,
         ts.median_score,
         ts.max_score,
         COALESCE(ht.hot_questions,0) AS hot_questions,
         COALESCE(ht.hot_questions::numeric / NULLIF(ts.question_count,0),0) AS hot_ratio,
         COALESCE(tpc.user_id,-1) AS top_contributor_user_id,
         COALESCE(u.DisplayName,'<anonymous>') AS top_contributor_name,
         COALESCE(tpc.answer_score_sum,0) AS top_contributor_score_sum,
         COALESCE(tpc.answers_count,0) AS top_contributor_answers,
         COALESCE(tls.sum_total_links,0) AS sum_total_links,
         COALESCE(tls.sum_total_incoming,0) AS sum_total_incoming,
         COALESCE(tas.sum_answers,0) AS sum_answers,
         COALESCE(tas.avg_answer_score,0) AS avg_answer_score,
         ROUND( (COALESCE(ts.total_views,0) * 0.6 + COALESCE(tas.sum_answers,0) * 50 + COALESCE(tpc.answer_score_sum,0) * 10)::numeric / NULLIF(ts.question_count,0), 2) AS tag_popularity_index,
         ROW_NUMBER() OVER (ORDER BY (COALESCE(ts.total_views,0) * 0.6 + COALESCE(tas.sum_answers,0) * 50 + COALESCE(tpc.answer_score_sum,0) * 10) DESC NULLS LAST) AS popularity_rank
  FROM tag_stats ts
  LEFT JOIN hot_tag_counts ht ON ht.tag = ts.tag
  LEFT JOIN tag_top_contributor_one tpc ON tpc.tag = ts.tag
  LEFT JOIN Users u ON u.Id = tpc.user_id
  LEFT JOIN tag_link_stats tls ON tls.tag = ts.tag
  LEFT JOIN tag_answer_stats tas ON tas.tag = ts.tag
)

SELECT
  f.popularity_rank,
  f.tag,
  f.question_count,
  f.total_views,
  f.avg_score,
  f.median_score,
  f.max_score,
  f.hot_questions,
  f.hot_ratio,
  f.top_contributor_user_id,
  f.top_contributor_name,
  f.top_contributor_score_sum,
  f.top_contributor_answers,
  f.sum_total_links,
  f.sum_total_incoming,
  f.sum_answers,
  f.avg_answer_score,
  f.tag_popularity_index,
  ROUND(100 * PERCENT_RANK() OVER (ORDER BY f.tag_popularity_index DESC), 2) AS tag_popularity_percentile,
  ROUND(AVG(f.tag_popularity_index) OVER (ORDER BY f.tag_popularity_index DESC ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_top3,
  CASE WHEN f.tag IN (SELECT tag FROM hot_and_reputable_tags) THEN true ELSE false END AS hot_and_reputable,
  (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Title ILIKE '%' || f.tag || '%') AS tag_in_title_count,
  (SELECT AVG(sub.age_days) FROM (
      SELECT EXTRACT(EPOCH FROM (now() - p.CreationDate))/86400 AS age_days
      FROM Posts p
      JOIN tagged_questions tq ON p.Id = tq.question_id
      WHERE tq.tag = f.tag
      ORDER BY p.Score DESC NULLS LAST
      LIMIT 3
  ) sub) AS avg_age_days_top3,
  COALESCE(qs.sample_question_id, -1) AS sample_question_id,
  qs.sample_title,
  qs.sample_score,
  qs.sample_views,
  qs.sample_upvotes,
  qs.sample_comments,
  CONCAT(
    CASE WHEN f.hot_ratio > 0.1 THEN 'HOT' WHEN f.avg_score >= 3 THEN 'HIGH-SCORING' ELSE 'STEADY' END,
    ' | ', COALESCE(NULLIF(f.top_contributor_name,''), 'NoTopContributor'),
    ' | popIdx=', COALESCE(ROUND(f.tag_popularity_index,2)::text, '0')
  ) AS insight
FROM final_tag_metrics f
LEFT JOIN LATERAL (
  SELECT p.Id AS sample_question_id,
         p.Title AS sample_title,
         p.Score AS sample_score,
         p.ViewCount AS sample_views,
         COALESCE(vs.upvotes,0) AS sample_upvotes,
         COALESCE(cs.comment_count,0) AS sample_comments
  FROM tagged_questions tq
  JOIN Posts p ON p.Id = tq.question_id AND tq.tag = f.tag
  LEFT JOIN vote_stats vs ON vs.post_id = p.Id
  LEFT JOIN comment_stats cs ON cs.post_id = p.Id
  ORDER BY (COALESCE(p.ViewCount,0) * 0.7 + COALESCE(vs.upvotes,0) * 50 + COALESCE(cs.comment_count,0) * 10 + COALESCE(p.Score,0) * 100) DESC NULLS LAST
  LIMIT 1
) qs ON true
ORDER BY f.popularity_rank
LIMIT 100;