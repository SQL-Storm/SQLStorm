-- {"query": "190.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2270} 
WITH
-- basic user aggregates
user_agg AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_count,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
    COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)),0) AS total_post_score,
    MAX(p.LastActivityDate) AS last_activity,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes_received,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes_received
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
-- explode tags from questions and count per user-tag
user_tags AS (
  SELECT
    ua.user_id,
    trim(tag) AS tag,
    COUNT(*) AS tag_uses
  FROM user_agg ua
  JOIN Posts q ON q.OwnerUserId = ua.user_id AND q.PostTypeId = 1 AND q.Tags IS NOT NULL
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags FROM 2 FOR (length(q.Tags)-2)), '><')) AS tag
  ) t
  GROUP BY ua.user_id, trim(tag)
),
-- top tag per user (ties broken by alphabetical)
top_tag_per_user AS (
  SELECT DISTINCT ON (ut.user_id)
    ut.user_id,
    ut.tag AS top_tag,
    ut.tag_uses
  FROM user_tags ut
  ORDER BY ut.user_id, ut.tag_uses DESC, ut.tag
),
-- per-user answer score distribution and median (correlated subquery for median)
answer_stats AS (
  SELECT
    u.Id AS user_id,
    COUNT(a.Id) AS total_answers,
    COALESCE(SUM(a.Score),0) AS sum_answer_score,
    COALESCE(AVG(a.Score),0) AS avg_answer_score,
    -- median using percentile_cont; falls back to NULL if no answers
    CASE WHEN COUNT(a.Id) = 0 THEN NULL
         ELSE percentile_cont(0.5) WITHIN GROUP (ORDER BY a.Score) END AS median_answer_score
  FROM Users u
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
  GROUP BY u.Id
),
-- recent activity windowed: last 90 days posts and activity rank
recent_activity AS (
  SELECT
    p.OwnerUserId AS user_id,
    p.PostTypeId,
    COUNT(*) FILTER (WHERE p.CreationDate >= now() - interval '90 days') AS recent_posts_90d,
    SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount,0) ELSE 0 END) FILTER (WHERE p.CreationDate >= now() - interval '90 days') AS recent_question_views_90d
  FROM Posts p
  GROUP BY p.OwnerUserId, p.PostTypeId
),
-- link/duplication behavior: how often user's questions were marked duplicates or linked
post_link_stats AS (
  SELECT
    p.OwnerUserId AS user_id,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS duplicates_marked, -- PostId is duplicate of RelatedPostId
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS links_out,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId IS NULL) AS links_unknown
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId
),
-- history churn: edits and deletions per user
history_stats AS (
  SELECT
    ph.UserId AS user_id,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS edits_count,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (12)) AS deletions_count,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10)) AS closes_count
  FROM PostHistory ph
  WHERE ph.UserId IS NOT NULL
  GROUP BY ph.UserId
),
-- assemble master user profile
master_users AS (
  SELECT
    ua.*,
    COALESCE(ts.top_tag, '[none]') AS top_tag,
    COALESCE(as2.total_answers,0) AS total_answers,
    as2.avg_answer_score,
    as2.median_answer_score,
    COALESCE(rl.recent_posts_90d,0) AS recent_posts_90d,
    COALESCE(rl.recent_question_views_90d,0) AS recent_question_views_90d,
    COALESCE(pls.duplicates_marked,0) AS duplicates_marked,
    COALESCE(pls.links_out,0) AS links_out,
    COALESCE(hs.edits_count,0) AS edits_count,
    COALESCE(hs.deletions_count,0) AS deletions_count,
    -- activity factor: weighted composite
    (COALESCE(ua.questions_count,0)*1.5 + COALESCE(ua.answers_count,0)*2 + COALESCE(ua.total_post_score,0)/10.0 + COALESCE(as2.avg_answer_score,0)*3
      + COALESCE(rl.recent_posts_90d,0)*2 - COALESCE(hs.deletions_count,0)*2) AS activity_score
  FROM user_agg ua
  LEFT JOIN top_tag_per_user ts ON ts.user_id = ua.user_id
  LEFT JOIN answer_stats as2 ON as2.user_id = ua.user_id
  LEFT JOIN recent_activity rl ON rl.user_id = ua.user_id
  LEFT JOIN post_link_stats pls ON pls.user_id = ua.user_id
  LEFT JOIN history_stats hs ON hs.user_id = ua.user_id
),
-- select top candidates by activity_score, apply ranking
ranked_users AS (
  SELECT
    m.*,
    RANK() OVER (ORDER BY activity_score DESC NULLS LAST, Reputation DESC NULLS LAST) AS activity_rank,
    ROW_NUMBER() OVER (ORDER BY COALESCE(m.median_answer_score, -99999) DESC, m.activity_score DESC) AS answer_rank
  FROM master_users m
),
-- identify users who gained badges recently (last year) and badge diversity
badge_agg AS (
  SELECT
    b.UserId AS user_id,
    COUNT(*) FILTER (WHERE b.Date >= now() - interval '1 year') AS badges_last_year,
    COUNT(DISTINCT b.Name) AS badge_name_diversity,
    COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges
  FROM Badges b
  GROUP BY b.UserId
),
-- sample of correlated subquery: count of unique answerers to each user's questions (per user)
unique_answerers_per_user AS (
  SELECT
    q.OwnerUserId AS user_id,
    COUNT(DISTINCT a.OwnerUserId) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS unique_answerers
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.OwnerUserId
)
SELECT
  ru.user_id,
  ru.DisplayName,
  ru.Reputation,
  ru.activity_rank,
  ru.answer_rank,
  ru.questions_count,
  ru.answers_count,
  ru.total_post_score,
  COALESCE(ru.top_tag,'[none]') AS top_tag,
  ru.total_answers,
  ru.avg_answer_score,
  ru.median_answer_score,
  ru.recent_posts_90d,
  ru.recent_question_views_90d,
  ru.duplicates_marked,
  ru.links_out,
  ru.edits_count,
  ru.deletions_count,
  COALESCE(bad.badges_last_year,0) AS badges_last_year,
  COALESCE(bad.badge_name_diversity,0) AS badge_name_diversity,
  COALESCE(uap.unique_answerers,0) AS unique_answerers_to_questions,
  -- string construction with null logic for display
  COALESCE(ru.DisplayName, 'user_' || ru.user_id::text) ||
    ' (rep:' || ru.Reputation::text || ', act:' || ROUND(ru.activity_score::numeric,2)::text || ')' AS summary,
  -- boolean-ish complex predicate: "healthy contributor"
  CASE
    WHEN ru.questions_count + ru.answers_count >= 5
      AND COALESCE(ru.avg_answer_score,0) >= 1.0
      AND COALESCE(bad.badges_last_year,0) >= 1
    THEN TRUE
    ELSE FALSE
  END AS is_healthy_contributor
FROM ranked_users ru
LEFT JOIN badge_agg bad ON bad.user_id = ru.user_id
LEFT JOIN unique_answerers_per_user uap ON uap.user_id = ru.user_id
-- only include active users with at least one post and non-zero activity_score
WHERE (ru.questions_count + ru.answers_count) > 0
  AND (ru.activity_score IS NOT NULL)
ORDER BY ru.activity_rank
LIMIT 100;