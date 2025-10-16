-- {"query": "103.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2638} 
WITH
-- basic aggregates per user
user_activity AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.CreationDate, to_timestamp(0)) AS created_at,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS q_count,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS a_count,
    COUNT(DISTINCT c.Id) AS comment_count,
    COUNT(DISTINCT b.Id) AS badge_count,
    MAX(p.LastActivityDate) AS last_post_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
-- compute per-post derived metrics + tag explosion for questions
posts_enriched AS (
  SELECT
    p.*,
    pt.Name AS post_type,
    COALESCE(p.Score,0) AS score0,
    COALESCE(p.ViewCount,0) AS views0,
    COALESCE(p.AnswerCount,0) AS answers0,
    -- split tags into one row per tag for questions (PostTypeId = 1)
    CASE WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL
         THEN regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), E'><')
         ELSE NULL END AS tag
  FROM Posts p
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
),
-- aggregate tag popularity and average question metrics
tag_stats AS (
  SELECT
    tag,
    COUNT(*) AS questions_with_tag,
    AVG(score0) AS avg_q_score,
    AVG(views0) AS avg_q_views,
    SUM(CASE WHEN AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_count
  FROM posts_enriched
  WHERE tag IS NOT NULL
  GROUP BY tag
),
-- link graph centrality-ish metrics per post (number of outgoing/incoming links)
post_link_stats AS (
  SELECT
    p.Id,
    COALESCE(out_links,0) AS out_links,
    COALESCE(in_links,0) AS in_links,
    COALESCE(out_links,0) + COALESCE(in_links,0) AS total_links
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS out_links FROM PostLinks GROUP BY PostId
  ) ol ON ol.PostId = p.Id
  LEFT JOIN (
    SELECT RelatedPostId AS Id, COUNT(*) AS in_links FROM PostLinks GROUP BY RelatedPostId
  ) il ON il.Id = p.Id
),
-- windowed ranking of posts per user by score, ties broken by recent activity and id
user_top_posts AS (
  SELECT
    p.Id AS post_id,
    p.OwnerUserId AS owner_id,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.LastActivityDate DESC NULLS LAST, p.Id) AS rn,
    RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS rnk
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
-- compute per-user answer quality including correlated subquery for accepted answers and avg answer score against peers
user_answer_quality AS (
  SELECT
    u.Id AS user_id,
    COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS answers_posted,
    SUM(a.Score) FILTER (WHERE a.PostTypeId = 2) AS answers_score_sum,
    SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_as_answer_count,
    -- correlated subquery: user's avg answer score relative to average answer score for same parent question's answers
    AVG(
      (SELECT AVG(a2.Score)::numeric
       FROM Posts a2
       WHERE a2.ParentId = a.ParentId AND a2.PostTypeId = 2
      ) )::numeric AS avg_peer_answer_score_for_user_answers
  FROM Users u
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  LEFT JOIN Posts q ON q.Id = a.ParentId -- parent question of the answer
  GROUP BY u.Id
),
-- badge breakdown pivot-like with string aggregation and NULL handling
user_badge_detail AS (
  SELECT
    b.UserId AS user_id,
    COUNT(*) FILTER (WHERE b.Class = 1)::int AS gold,
    COUNT(*) FILTER (WHERE b.Class = 2)::int AS silver,
    COUNT(*) FILTER (WHERE b.Class = 3)::int AS bronze,
    STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) FILTER (WHERE b.Name IS NOT NULL) AS badge_names
  FROM Badges b
  GROUP BY b.UserId
),
-- recent edit history summary using correlated subqueries and JSON aggregation for complexity
recent_edit_summary AS (
  SELECT
    p.Id AS post_id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    COALESCE((
      SELECT json_agg(json_build_object('hist_id', ph.Id, 'type', pht.Name, 'user', ph.UserId, 'when', ph.CreationDate))
      FROM PostHistory ph
      LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
      WHERE ph.PostId = p.Id
      ORDER BY ph.CreationDate DESC
      LIMIT 5
    ) , '[]'::json) AS recent_history
  FROM Posts p
),
-- combine question and answer aggregates with a set operator to stress planner
qa_union AS (
  SELECT
    'question'::text AS kind,
    p.Id AS post_id,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.Tags
  FROM Posts p WHERE p.PostTypeId = 1
  UNION ALL
  SELECT
    'answer'::text AS kind,
    p.Id AS post_id,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    NULL::int AS AnswerCount,
    NULL::varchar AS Tags
  FROM Posts p WHERE p.PostTypeId = 2
),
-- final user summary joining many CTEs, demonstrating NULL logic and complex expressions
final_user_summary AS (
  SELECT
    ua.user_id,
    ua.DisplayName,
    ua.Reputation,
    ua.q_count,
    ua.a_count,
    ua.comment_count,
    ua.badge_count,
    ubd.gold,
    ubd.silver,
    ubd.bronze,
    COALESCE(ubd.badge_names, '(none)') AS badges_list,
    COALESCE(uaq.answers_posted,0) AS answers_posted,
    COALESCE(uaq.answers_score_sum,0) AS answers_score_sum,
    COALESCE(uq_top.top_question_id, -1) AS representative_top_question_id,
    COALESCE(pls.total_links, 0) AS total_links_on_rep_question,
    CASE
      WHEN ua.a_count = 0 AND ua.q_count = 0 THEN 'inactive'
      WHEN ua.Reputation > 20000 THEN 'legend'
      WHEN ua.Reputation > 5000 THEN 'expert'
      WHEN ua.Reputation > 1000 THEN 'contributor'
      ELSE 'novice'
    END AS user_tier,
    -- compute a "health" score mixing normalized reputation, answers, badges and recent activity
    (
      LEAST(1.0, GREATEST(0.0, ua.Reputation/10000.0)) * 0.4
      + LEAST(1.0, GREATEST(0.0, (ua.a_count::numeric / NULLIF(GREATEST(1, ua.q_count),0)) )) * 0.25
      + LEAST(1.0, ubd.gold*0.05 + ubd.silver*0.02 + ubd.bronze*0.01) * 0.2
      + CASE WHEN ua.last_post_activity IS NOT NULL AND ua.last_post_activity > now() - interval '180 days' THEN 0.15 ELSE 0 END
    )::numeric(5,4) AS health_score
  FROM user_activity ua
  LEFT JOIN user_badge_detail ubd ON ubd.user_id = ua.user_id
  LEFT JOIN user_answer_quality uaq ON uaq.user_id = ua.user_id
  LEFT JOIN LATERAL (
    SELECT p.Id AS top_question_id
    FROM Posts p
    WHERE p.OwnerUserId = ua.user_id AND p.PostTypeId = 1
    ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST
    LIMIT 1
  ) uq_top ON true
  LEFT JOIN post_link_stats pls ON pls.Id = uq_top.top_question_id
)
SELECT
  fus.*,
  -- enrich with tag trends: top 3 tags (by questions_with_tag) that this user's top question uses
  COALESCE(
    (SELECT STRING_AGG(ts.tag || ' (' || ts.questions_with_tag || ')', ', ' ORDER BY ts.questions_with_tag DESC)
     FROM (
       SELECT DISTINCT tag FROM posts_enriched pe
       WHERE pe.OwnerUserId = fus.user_id AND pe.PostTypeId = 1 AND pe.tag IS NOT NULL
       ORDER BY 1
       LIMIT 3
     ) t
     LEFT JOIN tag_stats ts ON ts.tag = t.tag
    ), '(no top tags)'
  ) AS top_tags_with_popularity,
  -- the user's median answer score computed via windowing
  (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY COALESCE(p.Score,0))
   FROM Posts p WHERE p.OwnerUserId = fus.user_id AND p.PostTypeId = 2
  ) AS median_answer_score,
  -- sample of recent history for representative top question (json)
  (SELECT res.recent_history FROM recent_edit_summary res WHERE res.post_id = fus.representative_top_question_id) AS rep_top_q_recent_history,
  -- contrived correlated existence checks
  CASE
    WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = fus.user_id AND v.VoteTypeId = 2) THEN 'has_upvoted'
    WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = fus.user_id AND v.VoteTypeId = 3) THEN 'has_downvoted_only'
    ELSE 'no_votes_cast'
  END AS voting_behavior,
  -- include a small list of top answers by this user using the union CTE and window ranking
  (SELECT STRING_AGG(kind || ':' || post_id::text || ':' || COALESCE(score::text,'0'), '; ')
   FROM (
     SELECT q.kind, q.post_id, q.Score
     FROM qa_union q
     WHERE q.OwnerUserId = fus.user_id
     ORDER BY q.Score DESC NULLS LAST, q.post_id
     LIMIT 5
   ) x
  ) AS sample_posts
FROM final_user_summary fus
-- pick a challenging slice: active users with at least one post in last year or high rep
WHERE (fus.last_post_activity IS NOT NULL AND fus.last_post_activity > now() - interval '365 days') OR fus.Reputation > 5000
ORDER BY fus.health_score DESC, fus.Reputation DESC
LIMIT 250;