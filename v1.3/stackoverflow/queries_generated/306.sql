-- {"query": "306.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20098} 
WITH
expanded_tags AS (
  SELECT
    p.Id AS post_id,
    p.OwnerUserId,
    p.CreationDate,
    lower(regexp_split_to_table(substring(p.Tags from 2 for greatest(char_length(p.Tags) - 2, 0)), '><')) AS tag
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
answer_votes AS (
  SELECT
    a.Id AS answer_id,
    a.ParentId AS question_id,
    a.OwnerUserId AS owner_id,
    a.CreationDate AS answer_date,
    q.CreationDate AS question_date,
    CASE WHEN a.CreationDate IS NOT NULL AND q.CreationDate IS NOT NULL THEN extract(epoch FROM (a.CreationDate - q.CreationDate))::int ELSE NULL END AS response_seconds,
    a.Score AS answer_score,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    (q.AcceptedAnswerId = a.Id) AS is_accepted
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  LEFT JOIN Votes v ON v.PostId = a.Id
  WHERE a.PostTypeId = 2
  GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, q.CreationDate, a.Score, q.AcceptedAnswerId
),
question_answer_aggs AS (
  SELECT
    q.Id AS question_id,
    q.OwnerUserId AS question_owner,
    COUNT(av.answer_id) AS answer_count,
    COALESCE(AVG(av.answer_score),0) AS avg_answer_score,
    COALESCE(percentile_cont(0.5) WITHIN GROUP (ORDER BY av.response_seconds), NULL) AS median_response_secs,
    MIN(av.response_seconds) AS fastest_response,
    MAX(av.response_seconds) AS slowest_response,
    SUM(CASE WHEN av.is_accepted THEN 1 ELSE 0 END) AS accepted_count
  FROM Posts q
  LEFT JOIN answer_votes av ON av.question_id = q.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.OwnerUserId
),
tag_question_join AS (
  SELECT
    et.tag,
    et.post_id AS question_id,
    qa.answer_count,
    qa.avg_answer_score,
    qa.median_response_secs,
    qa.accepted_count,
    p.ViewCount,
    p.Score AS question_score,
    p.FavoriteCount
  FROM expanded_tags et
  JOIN Posts p ON p.Id = et.post_id
  LEFT JOIN question_answer_aggs qa ON qa.question_id = et.post_id
),
tag_aggregates AS (
  SELECT
    tag,
    COUNT(*) AS question_count,
    COALESCE(SUM(ViewCount),0) AS total_views,
    COALESCE(AVG(avg_answer_score),0) AS avg_answer_score_per_tag,
    COALESCE(percentile_cont(0.75) WITHIN GROUP (ORDER BY median_response_secs NULLS LAST),0) AS p75_response_secs,
    MAX(question_score) AS max_question_score,
    SUM(COALESCE(accepted_count,0)) AS accepted_answers_total,
    (COALESCE(SUM(ViewCount),0)::numeric / GREATEST(COUNT(*),1)) AS avg_views_per_question,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(ViewCount),0) DESC) AS tag_pop_rank,
    DENSE_RANK() OVER (ORDER BY SUM(COALESCE(accepted_count,0)) DESC) AS tag_accept_rank
  FROM tag_question_join
  GROUP BY tag
),
user_tag_answers AS (
  SELECT
    t.tag,
    u.Id AS user_id,
    u.DisplayName,
    COALESCE(u.Reputation,0) AS reputation,
    COALESCE(cnt.answers_by_user,0) AS answers_in_tag,
    COALESCE(cnt.accepted_answers_in_tag,0) AS accepted_in_tag,
    COALESCE(cnt.avg_response_secs, NULL) AS avg_response_secs_user_tag,
    cnt.last_answer_date
  FROM (SELECT tag FROM tag_aggregates) t
  LEFT JOIN LATERAL (
    SELECT
      a.OwnerUserId AS uid,
      COUNT(*)::int AS answers_by_user,
      SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END)::int AS accepted_answers_in_tag,
      AVG(extract(epoch FROM (a.CreationDate - q.CreationDate)))::int AS avg_response_secs,
      MAX(a.CreationDate) AS last_answer_date
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    JOIN expanded_tags et ON et.post_id = q.Id
    WHERE et.tag = t.tag AND a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
    ORDER BY answers_by_user DESC NULLS LAST
    LIMIT 1
  ) cnt ON TRUE
  LEFT JOIN Users u ON u.Id = cnt.uid
),
prolific_voters AS (
  SELECT v.UserId AS user_id
  FROM Votes v
  WHERE v.VoteTypeId = 2 AND v.UserId IS NOT NULL
  GROUP BY v.UserId
  HAVING COUNT(*) >= 50
),
badge_winners AS (
  SELECT b.UserId AS user_id
  FROM Badges b
  WHERE b.Class = 1
  GROUP BY b.UserId
  HAVING COUNT(*) >= 1
),
voters_and_badged AS (
  SELECT user_id FROM prolific_voters
  INTERSECT
  SELECT user_id FROM badge_winners
),
user_leaderboard AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    q.questions_posted,
    a.answers_posted,
    COALESCE(p.total_post_score,0) AS total_post_score,
    COALESCE(vu.total_upvotes_received,0) AS total_upvotes_received,
    COALESCE(vd.total_downvotes_received,0) AS total_downvotes_received,
    m.median_response_secs,
    ROW_NUMBER() OVER (ORDER BY COALESCE(p.total_post_score,0) DESC NULLS LAST, u.Reputation DESC NULLS LAST) AS global_rank,
    EXISTS (SELECT 1 FROM voters_and_badged vb WHERE vb.user_id = u.Id) AS elite_flag
  FROM Users u
  LEFT JOIN LATERAL (SELECT COUNT(*) AS questions_posted FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) q ON TRUE
  LEFT JOIN LATERAL (SELECT COUNT(*) AS answers_posted FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) a ON TRUE
  LEFT JOIN LATERAL (SELECT COALESCE(SUM(p.Score),0) AS total_post_score FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)) p ON TRUE
  LEFT JOIN LATERAL (SELECT COUNT(*) AS total_upvotes_received FROM Votes vv JOIN Posts p2 ON p2.Id = vv.PostId WHERE p2.OwnerUserId = u.Id AND vv.VoteTypeId = 2) vu ON TRUE
  LEFT JOIN LATERAL (SELECT COUNT(*) AS total_downvotes_received FROM Votes vv JOIN Posts p2 ON p2.Id = vv.PostId WHERE p2.OwnerUserId = u.Id AND vv.VoteTypeId = 3) vd ON TRUE
  LEFT JOIN LATERAL (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS median_response_secs FROM Posts a JOIN Posts q ON q.Id = a.ParentId WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) m ON TRUE
),
post_graph AS (
  SELECT pl.PostId AS start_post, pl.RelatedPostId AS linked_post, pl.LinkTypeId, 1 AS depth, ARRAY[pl.PostId, pl.RelatedPostId] AS path
  FROM PostLinks pl
  WHERE pl.PostId IS NOT NULL AND pl.RelatedPostId IS NOT NULL
  UNION ALL
  SELECT pg.start_post, pl.RelatedPostId, pl.LinkTypeId, pg.depth + 1 AS depth, pg.path || pl.RelatedPostId
  FROM post_graph pg
  JOIN PostLinks pl ON pl.PostId = pg.linked_post
  WHERE NOT pl.RelatedPostId = ANY(pg.path) AND pg.depth < 8
),
post_components AS (
  SELECT start_post, MIN(depth) AS min_depth, COUNT(DISTINCT linked_post) AS reachable_count
  FROM post_graph
  GROUP BY start_post
),
final AS (
  SELECT
    t.tag,
    t.question_count,
    t.total_views,
    t.avg_views_per_question,
    t.avg_answer_score_per_tag,
    t.p75_response_secs,
    COALESCE(uta.user_id, -1) AS top_user_id,
    COALESCE(uta.DisplayName, '(none)') AS top_user_display,
    COALESCE(uta.reputation,0) AS top_user_reputation,
    COALESCE(uta.answers_in_tag,0) AS top_user_answers_in_tag,
    COALESCE(uta.accepted_in_tag,0) AS top_user_accepted_in_tag,
    CASE WHEN t.question_count > 0 THEN (t.accepted_answers_total::numeric / t.question_count) ELSE 0 END AS accept_rate_per_question,
    pc.reachable_count AS related_post_reach,
    (SELECT p2.Id FROM Posts p2 JOIN expanded_tags et2 ON et2.post_id = p2.Id WHERE et2.tag = t.tag ORDER BY p2.Score DESC NULLS LAST, p2.ViewCount DESC NULLS LAST LIMIT 1) AS top_question_id,
    (SELECT LEFT(regexp_replace(COALESCE(p3.Body,''), '<[^>]+>', '', 'g'),200) FROM Posts p3 JOIN expanded_tags et3 ON et3.post_id = p3.Id WHERE et3.tag = t.tag ORDER BY p3.Score DESC NULLS LAST LIMIT 1) AS top_question_snippet,
    RANK() OVER (ORDER BY COALESCE(t.total_views,0) DESC, COALESCE(t.avg_answer_score_per_tag,0) DESC) AS combined_rank,
    (ln(GREATEST(t.total_views,1)::numeric) * GREATEST(1 + COALESCE(t.avg_answer_score_per_tag,0), 0.01) / GREATEST(1 + COALESCE(t.p75_response_secs,0)::numeric / 86400, 0.01))::numeric(12,4) AS tag_health_score,
    (COALESCE(t.max_question_score,0)::numeric * COALESCE(t.avg_answer_score_per_tag,0) / NULLIF(GREATEST(t.avg_views_per_question,1)::numeric,0))::numeric(12,4) AS tag_complexity_score
  FROM tag_aggregates t
  LEFT JOIN user_tag_answers uta ON uta.tag = t.tag
  LEFT JOIN LATERAL (SELECT question_id FROM tag_question_join WHERE tag = t.tag ORDER BY ViewCount DESC NULLS LAST LIMIT 1) topq ON TRUE
  LEFT JOIN post_components pc ON pc.start_post = topq.question_id
)
SELECT
  f.tag,
  f.question_count,
  f.total_views,
  f.avg_views_per_question,
  f.avg_answer_score_per_tag,
  f.p75_response_secs,
  f.tag_health_score,
  f.tag_complexity_score,
  f.top_question_id,
  f.top_question_snippet,
  f.top_user_id,
  f.top_user_display,
  f.top_user_reputation,
  f.top_user_answers_in_tag,
  f.top_user_accepted_in_tag,
  ul.global_rank AS top_user_global_rank,
  ul.median_response_secs AS top_user_median_response_secs,
  f.combined_rank,
  f.related_post_reach,
  (SELECT array_to_string(array_agg(sub.tag ORDER BY sub.cnt DESC), ',')
   FROM (
     SELECT et2.tag, COUNT(*) AS cnt
     FROM expanded_tags et2
     JOIN expanded_tags etq ON etq.post_id = et2.post_id AND etq.tag <> et2.tag
     WHERE etq.tag = f.tag
     GROUP BY et2.tag
     ORDER BY cnt DESC
     LIMIT 5
   ) sub
  ) AS top_tag_cooccurrence
FROM final f
LEFT JOIN user_leaderboard ul ON ul.Id = f.top_user_id
ORDER BY f.combined_rank, f.total_views DESC NULLS LAST
LIMIT 200;