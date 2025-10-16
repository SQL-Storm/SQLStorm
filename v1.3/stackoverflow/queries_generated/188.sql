-- {"query": "188.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2253} 
WITH
-- recent activity per post with parsed tags
post_tags AS (
  SELECT
    p.Id AS post_id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    CASE WHEN p.Tags IS NULL THEN ARRAY[]::text[]
         ELSE string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
    END AS tag_arr
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '3 years'
),
-- aggregate votes with conditional sums and correlated subquery for last vote per post
vote_aggs AS (
  SELECT
    v.PostId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
    SUM(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) AS total_bounty,
    MAX(v.CreationDate) AS last_vote_at,
    -- correlated subquery: last vote type per post
    (SELECT vt.Name FROM VoteTypes vt WHERE vt.Id =
      (SELECT v2.VoteTypeId FROM Votes v2 WHERE v2.PostId = v.PostId ORDER BY v2.CreationDate DESC LIMIT 1)
    ) AS last_vote_type
  FROM Votes v
  GROUP BY v.PostId
),
-- compute per-user post stats with window functions and NULL logic
user_posts AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS q_count,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS a_count,
    COUNT(p.Id) AS total_posts,
    SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS total_post_score,
    MAX(p.CreationDate) AS last_post_at,
    -- window: user's highest scoring post id and score
    (ARRAY_AGG(p.Id ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC))[1] AS top_post_id,
    (ARRAY_AGG(p.Score ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC))[1] AS top_post_score,
    -- detect if user has any accepted answers
    SUM(CASE WHEN p.PostTypeId = 2 AND EXISTS (
          SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = p.Id
        ) THEN 1 ELSE 0 END) AS accepted_answers_count
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- tag popularity across recent questions with lateral and complex expressions
tag_pop AS (
  SELECT
    t.tag,
    COUNT(*) AS questions_with_tag,
    SUM(pt.Score) AS sum_scores,
    AVG(COALESCE(pt.ViewCount,0))::numeric(12,2) AS avg_views,
    -- string expression: representative tag label normalized
    lower(regexp_replace(t.tag, '[^a-z0-9]', '', 'g')) AS tag_norm
  FROM post_tags pt
  CROSS JOIN LATERAL unnest(pt.tag_arr) AS t(tag)
  WHERE pt.PostTypeId = 1
  GROUP BY t.tag
),
-- top N tags with window ranking and filtering on null-safety
top_tags AS (
  SELECT *,
    RANK() OVER (ORDER BY questions_with_tag DESC, sum_scores DESC) AS rnk
  FROM tag_pop
  WHERE questions_with_tag > 0
),
-- combine post, votes and post history with outer joins and complex NULL logic
post_full AS (
  SELECT
    pt.post_id,
    pt.PostTypeId,
    pt.OwnerUserId,
    COALESCE(vg.upvotes,0) AS upvotes,
    COALESCE(vg.downvotes,0) AS downvotes,
    COALESCE(vg.total_bounty,0) AS total_bounty,
    COALESCE(ph_edits.edit_count,0) AS edit_count,
    pt.Score,
    pt.ViewCount,
    pt.Title,
    pt.tag_arr,
    -- calculate a "popularity" heuristic mixing score, views and upvote ratio with NULL guards
    (COALESCE(pt.Score,0) * 2 + COALESCE(pt.ViewCount,0)::numeric / GREATEST(1, NULLIF(COALESCE(vg.upvotes,0)+COALESCE(vg.downvotes,0),0)) + COALESCE(vg.upvotes,0) * 1.5 - COALESCE(vg.downvotes,0) * 2 + COALESCE(vg.total_bounty,0) * 0.1) AS popularity_score,
    vg.last_vote_at,
    vg.last_vote_type
  FROM post_tags pt
  LEFT JOIN vote_aggs vg ON vg.PostId = pt.post_id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS edit_count
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4,5,6,24) -- edits
    GROUP BY PostId
  ) ph_edits ON ph_edits.PostId = pt.post_id
),
-- user summaries joining user_posts and derived post metrics using correlated subqueries and NULL logic
user_summary AS (
  SELECT
    up.user_id,
    up.DisplayName,
    up.Reputation,
    up.q_count,
    up.a_count,
    up.total_posts,
    up.total_post_score,
    up.last_post_at,
    up.top_post_id,
    up.top_post_score,
    up.accepted_answers_count,
    -- correlated subquery: average popularity of user's posts in last 3 years
    (SELECT AVG(pf.popularity_score) FROM post_full pf WHERE pf.OwnerUserId = up.user_id) AS avg_post_popularity,
    -- number of distinct top tags for user's questions (NULL-safe)
    (SELECT COUNT(DISTINCT t) FROM (
       SELECT unnest(pt.tag_arr) AS t FROM Posts p JOIN LATERAL (
         SELECT string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag_arr
       ) AS pt ON true
       WHERE p.OwnerUserId = up.user_id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) s) AS distinct_question_tags
  FROM user_posts up
),
-- union: two different heavy-weight queries to exercise set operators and different plans
heavy_union AS (
  SELECT
    us.*,
    tt.tag AS favorite_tag,
    tt.rnk AS tag_rank,
    NULL::int AS extra_flag
  FROM user_summary us
  LEFT JOIN LATERAL (
    SELECT tag, rnk FROM top_tags tt WHERE tt.rnk <= 50 AND tt.tag ILIKE (us.DisplayName || '%') LIMIT 1
  ) tt ON true

  UNION ALL

  SELECT
    us.*,
    tt.tag AS favorite_tag,
    tt.rnk AS tag_rank,
    1::int AS extra_flag
  FROM user_summary us
  LEFT JOIN LATERAL (
    SELECT tag, rnk FROM top_tags tt WHERE tt.tag_norm = lower(regexp_replace(us.DisplayName, '[^a-z0-9]', '', 'g')) LIMIT 1
  ) tt ON true
),
-- final ranking combining metrics and window functions, plus complicated predicates
final_ranked AS (
  SELECT
    hu.*,
    COALESCE(us.avg_post_popularity, 0) AS popularity,
    -- custom composite score
    (COALESCE(us.avg_post_popularity,0) * 0.4 + COALESCE(us.Reputation,0) / 1000.0 + COALESCE(us.accepted_answers_count,0) * 0.3 + GREATEST(COALESCE(us.total_posts,0),1) * 0.05) AS composite_score,
    ROW_NUMBER() OVER (ORDER BY (COALESCE(us.avg_post_popularity,0) * 0.4 + COALESCE(us.Reputation,0) / 1000.0 + COALESCE(us.accepted_answers_count,0) * 0.3) DESC, us.total_posts DESC NULLS LAST) AS overall_rank
  FROM heavy_union hu
  JOIN user_summary us ON us.user_id = hu.user_id
)
SELECT
  fr.overall_rank,
  fr.user_id,
  fr.DisplayName,
  fr.Reputation,
  fr.total_posts,
  fr.q_count,
  fr.a_count,
  fr.accepted_answers_count,
  ROUND(fr.popularity::numeric,2) AS avg_popularity,
  ROUND(fr.composite_score::numeric,4) AS composite_score,
  fr.favorite_tag,
  fr.tag_rank,
  fr.extra_flag,
  -- correlated scalar subquery returning recent comment text snippet for the user's top post (if any)
  (SELECT substring(c.Text from 1 for 120) FROM Comments c
   WHERE c.PostId = fr.top_post_id AND c.UserId IS NOT NULL
   ORDER BY c.CreationDate DESC LIMIT 1) AS recent_comment_snippet,
  -- boolean expression with NULL logic: active_recent_user
  (CASE WHEN fr.last_post_at IS NOT NULL AND fr.last_post_at > now() - interval '90 days' THEN true ELSE false END) AS active_recent_user,
  -- complex predicate: flagged if reputation low but many accepted answers or high composite
  (CASE WHEN fr.Reputation < 100 AND (fr.accepted_answers_count >= 3 OR fr.composite_score > 1.5) THEN true ELSE false END) AS low_rep_but_effective
FROM final_ranked fr
WHERE fr.total_posts > 0
  AND (fr.composite_score IS NOT NULL AND fr.composite_score > 0.1)
ORDER BY fr.overall_rank
LIMIT 250;