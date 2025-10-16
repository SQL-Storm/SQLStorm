-- {"query": "117.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2720} 
WITH
-- flatten posts into user-owned rows including tag breakdown
user_posts AS (
  SELECT
    p.Id AS post_id,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId AS user_id,
    p.CreationDate,
    p.Score,
    COALESCE(p.ViewCount,0) AS view_count,
    COALESCE(p.AnswerCount,0) AS answer_count,
    p.Title,
    p.Tags,
    -- derive tag array (null-safe)
    CASE WHEN p.Tags IS NULL THEN ARRAY[]::text[] ELSE regexp_split_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><') END AS tag_array
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
-- explode tags and compute per-user per-tag counts (may be 0)
user_tag_exploded AS (
  SELECT
    up.user_id,
    trim(tg.tag) AS tag,
    count(*) FILTER (WHERE up.PostTypeId = 1) AS question_count,
    count(*) FILTER (WHERE up.PostTypeId = 2) AS answer_count
  FROM user_posts up
  LEFT JOIN LATERAL (
    SELECT unnest(up.tag_array) AS tag
  ) tg ON true
  GROUP BY up.user_id, trim(tg.tag)
),
-- aggregate tag diversity + top tag per user
user_tag_metrics AS (
  SELECT
    ute.user_id,
    count(DISTINCT CASE WHEN tag <> '' THEN tag END) AS distinct_tags,
    max(question_count + answer_count) AS max_posts_in_single_tag,
    -- pick top tag by posts then alphabetically
    (SELECT tag FROM user_tag_exploded ute2 WHERE ute2.user_id = ute.user_id ORDER BY (ute2.question_count + ute2.answer_count) DESC NULLS LAST, ute2.tag LIMIT 1) AS top_tag
  FROM user_tag_exploded ute
  GROUP BY ute.user_id
),
-- badge-derived score: gold=5,silver=3,bronze=1, tag-based counted differently
badge_points AS (
  SELECT
    b.UserId AS user_id,
    sum(
      CASE
        WHEN b.Class = 1 THEN 5
        WHEN b.Class = 2 THEN 3
        WHEN b.Class = 3 THEN 1
        ELSE 0
      END
    ) + sum(CASE WHEN b.TagBased = true THEN 1 ELSE 0 END) * 0.25 AS badge_score,
    count(*) AS badge_count
  FROM Badges b
  GROUP BY b.UserId
),
-- vote-derived metrics: upvotes (2), downvotes (-1), accepts (4), other vote types weighted
vote_points AS (
  SELECT
    v.UserId AS voter_user_id,
    v.PostId,
    SUM(
      CASE v.VoteTypeId
        WHEN 2 THEN 2   -- upvote
        WHEN 3 THEN -1  -- downvote
        WHEN 1 THEN 4   -- accepted by originator
        WHEN 5 THEN 1   -- favorite
        WHEN 8 THEN 2   -- bounty start (partial credit)
        ELSE 0
      END
    ) AS vote_point_sum
  FROM Votes v
  GROUP BY v.UserId, v.PostId
),
-- per-post aggregate of votes (null-safe)
post_vote_agg AS (
  SELECT
    p.Id AS post_id,
    COALESCE(SUM(
      CASE v.VoteTypeId
        WHEN 2 THEN 2
        WHEN 3 THEN -1
        WHEN 1 THEN 4
        WHEN 5 THEN 1
        WHEN 8 THEN 2
        ELSE 0
      END
    ),0) AS post_vote_points,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS upvotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS downvotes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
),
-- last activity per user using posts/comments history and posthistory
user_last_activity AS (
  SELECT
    u.Id AS user_id,
    GREATEST(
      COALESCE(MAX(p.LastActivityDate), TIMESTAMP '1970-01-01'),
      COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01'),
      COALESCE(MAX(ph.CreationDate), TIMESTAMP '1970-01-01'),
      u.LastAccessDate
    ) AS last_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN PostHistory ph ON ph.UserId = u.Id
  GROUP BY u.Id, u.LastAccessDate
),
-- combine user-level metrics
user_post_aggregates AS (
  SELECT
    u.Id AS user_id,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS questions,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS answers,
    COALESCE(SUM(COALESCE(p.Score,0)),0) AS post_score_sum,
    COALESCE(SUM(p.view_count),0) AS total_views,
    COALESCE(SUM(COALESCE(pva.post_vote_points,0)),0) AS vote_points,
    MAX(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) AS last_post_date,
    -- correlated subquery: fetch most recent comment on any of their posts (text trimmed)
    (SELECT trim(substring(c2.Text FROM 1 FOR 200)) FROM Comments c2 WHERE c2.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = u.Id) ORDER BY c2.CreationDate DESC LIMIT 1) AS latest_comment_excerpt
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN post_vote_agg pva ON pva.post_id = p.Id
  GROUP BY u.Id
),
-- a synthetic activity score combining many signals with NULL-safe math
user_composite_score AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    upa.questions,
    upa.answers,
    upa.post_score_sum,
    upa.vote_points,
    upa.total_views,
    COALESCE(bp.badge_score,0) AS badge_score,
    COALESCE(utm.distinct_tags,0) AS distinct_tags,
    COALESCE(utm.top_tag,'') AS top_tag,
    COALESCE(ula.last_activity, u.LastAccessDate) AS last_activity,
    upa.latest_comment_excerpt,
    -- composite formula: reputation normalized, weighted contributions and recency decay
    (
      -- base from reputation and posts
      (LOG(NULLIF(u.Reputation,0) + 1) * 1.6)
      + (LOG(NULLIF(upa.post_score_sum,0) + 1) * 1.2)
      + (LOG(NULLIF(upa.vote_points,0) + 5) * 1.4)
      + (bp.badge_score * 0.9)
      + (LEAST(utm.distinct_tags,50) * 0.15)
      + (LOG(NULLIF(upa.total_views,0) + 2) * 0.25)
      -- recency multiplier: half-life ~180 days
    ) * (1 + EXP(-EXTRACT(EPOCH FROM (now() - COALESCE(ula.last_activity, u.LastAccessDate))) / (60*60*24*180))) AS raw_score_estimate
  FROM Users u
  LEFT JOIN user_post_aggregates upa ON upa.user_id = u.Id
  LEFT JOIN badge_points bp ON bp.user_id = u.Id
  LEFT JOIN user_tag_metrics utm ON utm.user_id = u.Id
  LEFT JOIN user_last_activity ula ON ula.user_id = u.Id
),
-- compute rank and windowed percentiles; include only active-ish users but keep a sample of inactive via UNION ALL
ranked_users AS (
  SELECT
    ucs.*,
    RANK() OVER (ORDER BY raw_score_estimate DESC NULLS LAST) AS rank_overall,
    NTILE(100) OVER (ORDER BY raw_score_estimate DESC NULLS LAST) AS percentile_rank,
    -- flag: prolific answerers with high accept rate (correlated subquery)
    (SELECT COALESCE(AVG(CASE WHEN a.AcceptedAnswerId = a.Id THEN 1.0 ELSE 0.0 END),0)
     FROM Posts a WHERE a.OwnerUserId = ucs.user_id AND a.PostTypeId = 2) AS self_accept_rate
  FROM user_composite_score ucs
),
-- produce a diagnostic union set: top N plus a stratified sample from lower percentiles
final_selection AS (
  SELECT * FROM ranked_users WHERE rank_overall <= 50
  UNION ALL
  SELECT * FROM ranked_users WHERE percentile_rank BETWEEN 90 AND 95
  UNION ALL
  SELECT * FROM ranked_users WHERE percentile_rank BETWEEN 50 AND 55
  UNION ALL
  -- include few low-ranked for edge-case performance
  SELECT * FROM ranked_users WHERE rank_overall > 1000 AND rank_overall <= 1010
)
SELECT
  fs.user_id,
  COALESCE(fs.DisplayName, ('user_' || fs.user_id::text)) AS display_name,
  fs.Reputation,
  fs.questions,
  fs.answers,
  fs.post_score_sum,
  fs.vote_points,
  round(fs.badge_score::numeric,2) AS badge_score,
  fs.distinct_tags,
  COALESCE(NULLIF(fs.top_tag,''),'(none)') AS top_tag,
  fs.last_activity,
  COALESCE(fs.latest_comment_excerpt,'') AS latest_comment_excerpt,
  round(fs.raw_score_estimate::numeric,4) AS raw_score_estimate,
  fs.rank_overall,
  fs.percentile_rank,
  round(COALESCE(fs.self_accept_rate,0)::numeric,3) AS self_accept_rate,
  -- complex inline expression demonstrating NULL logic and string ops
  CASE
    WHEN fs.rank_overall <= 10 THEN 'elite'
    WHEN fs.percentile_rank >= 90 THEN 'power'
    WHEN fs.raw_score_estimate IS NULL THEN 'unknown'
    ELSE concat('tier_', floor( (100 - fs.percentile_rank)::numeric / 10 )::int )
  END AS user_tier,
  -- show presence/absence across other tables via EXISTS correlated checks
  (CASE WHEN EXISTS(SELECT 1 FROM Comments c WHERE c.UserId = fs.user_id) THEN 1 ELSE 0 END) AS has_comments,
  (CASE WHEN EXISTS(SELECT 1 FROM Badges b WHERE b.UserId = fs.user_id) THEN 1 ELSE 0 END) AS has_badges,
  (CASE WHEN EXISTS(SELECT 1 FROM Posts p WHERE p.OwnerUserId = fs.user_id AND p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) THEN 1 ELSE 0 END) AS has_questions_with_accepts
FROM final_selection fs
ORDER BY fs.rank_overall NULLS LAST, fs.raw_score_estimate DESC NULLS LAST;