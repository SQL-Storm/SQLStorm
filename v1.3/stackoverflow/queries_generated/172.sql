-- {"query": "172.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2627} 
WITH
-- basic user aggregates for questions and answers
user_posts AS (
  SELECT
    u.Id AS user_id,
    coalesce(u.DisplayName, '<unknown>') AS display_name,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_posted,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_posted,
    SUM(COALESCE(p.Score,0)) AS total_post_score,
    AVG(NULLIF(p.Score,0)) FILTER (WHERE p.Score IS NOT NULL) AS avg_nonzero_score,
    MAX(p.LastActivityDate) AS last_activity,
    MIN(p.CreationDate) FILTER (WHERE p.PostTypeId = 1) AS first_question_date
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
-- badge breakdown including tag-based and class counts
user_badges AS (
  SELECT
    b.UserId AS user_id,
    COUNT(*) AS badge_total,
    SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS tag_based_badges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
    STRING_AGG(DISTINCT b.Name, ' | ' ORDER BY b.Name) AS distinct_badge_names
  FROM Badges b
  GROUP BY b.UserId
),
-- per-user tag usage derived from question tags (tags stored like '<t1><t2>')
user_tags AS (
  SELECT
    up.user_id,
    tag AS tag_name,
    COUNT(*) AS tag_count
  FROM Posts p
  JOIN user_posts up ON up.user_id = p.OwnerUserId
  CROSS JOIN LATERAL (
    SELECT trim(x) AS tag
    FROM unnest(
      CASE
        WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')
        ELSE ARRAY[]::text[]
      END
    ) x
  ) t
  WHERE p.PostTypeId = 1
  GROUP BY up.user_id, tag
),
-- top tag per user
top_tags AS (
  SELECT DISTINCT ON (user_id)
    user_id,
    tag_name AS top_tag,
    tag_count
  FROM user_tags
  ORDER BY user_id, tag_count DESC, tag_name
),
-- answer timings: time from question to accepted answer or average answer time
answer_metrics AS (
  SELECT
    a.OwnerUserId AS user_id,
    COUNT(a.Id) AS answers_given,
    AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600) FILTER (WHERE q.CreationDate IS NOT NULL) AS avg_answer_hours,
    AVG(a.Score) AS avg_answer_score,
    SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS accepted_count,
    SUM(CASE WHEN a.Score >= 5 THEN 1 ELSE 0 END) AS high_score_answers
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  WHERE a.PostTypeId = 2
  GROUP BY a.OwnerUserId
),
-- posts that are linked as duplicates (set operator: union questions duplicated or linked)
duplicate_and_linked_posts AS (
  SELECT pl.PostId, pl.RelatedPostId, lt.Name AS link_type
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.LinkTypeId IN (1,3) -- linked or duplicate
  UNION ALL
  SELECT pl.RelatedPostId AS PostId, pl.PostId AS RelatedPostId, 'REVERSE:' || lt.Name
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.LinkTypeId IN (1,3)
),
-- per-user duplicate/link exposures via their posts
user_link_exposure AS (
  SELECT
    p.OwnerUserId AS user_id,
    COUNT(DISTINCT d.RelatedPostId) AS distinct_linked_posts,
    SUM(CASE WHEN d.link_type ILIKE '%Duplicate%' OR d.link_type ILIKE '%3%' THEN 1 ELSE 0 END) AS duplicate_flags
  FROM Posts p
  LEFT JOIN duplicate_and_linked_posts d ON d.PostId = p.Id
  GROUP BY p.OwnerUserId
),
-- historical edits activity: edits made by user in PostHistory
user_edits AS (
  SELECT
    ph.UserId AS user_id,
    COUNT(*) AS edit_count,
    MIN(ph.CreationDate) AS first_edit,
    MAX(ph.CreationDate) AS last_edit,
    SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS edits_title_body_tags
  FROM PostHistory ph
  WHERE ph.UserId IS NOT NULL
  GROUP BY ph.UserId
),
-- score normalization and benchmarking values using window functions
bench AS (
  SELECT
    up.*,
    COALESCE(ub.badge_total,0) AS badge_total,
    COALESCE(ub.gold_badges,0) AS gold_badges,
    COALESCE(am.answers_given,0) AS answers_given,
    COALESCE(tle.top_tag, '<none>') AS top_tag,
    COALESCE(ule.distinct_linked_posts,0) AS linked_post_exposure,
    COALESCE(ue.edit_count,0) AS edit_count,
    -- compute a composite performance score
    (COALESCE(up.total_post_score,0) * 0.5)
    + (COALESCE(am.answers_given,0) * 2.0)
    + (COALESCE(ub.gold_badges,0) * 10)
    + (COALESCE(ub.silver_badges,0) * 3)
    - (COALESCE(ule.duplicate_flags,0) * 2)
    + (CASE WHEN up.last_activity > now() - INTERVAL '30 days' THEN 5 ELSE 0 END) AS perf_score_raw,
    -- normalize using percentile over partition
    RANK() OVER (ORDER BY
      (COALESCE(up.total_post_score,0) * 0.5)
      + (COALESCE(am.answers_given,0) * 2.0)
      + (COALESCE(ub.gold_badges,0) * 10)
      + (COALESCE(ub.silver_badges,0) * 3)
      - (COALESCE(ule.duplicate_flags,0) * 2)
      + (CASE WHEN up.last_activity > now() - INTERVAL '30 days' THEN 5 ELSE 0 END) DESC
    ) AS perf_rank,
    NTILE(10) OVER (ORDER BY COALESCE(up.total_post_score,0) DESC) AS score_decile
  FROM user_posts up
  LEFT JOIN user_badges ub ON ub.user_id = up.user_id
  LEFT JOIN answer_metrics am ON am.user_id = up.user_id
  LEFT JOIN top_tags tle ON tle.user_id = up.user_id
  LEFT JOIN user_link_exposure ule ON ule.user_id = up.user_id
  LEFT JOIN user_edits ue ON ue.user_id = up.user_id
),
-- correlated subquery example: compute for each user the nearest higher-scoring user and how much they trail by
nearest_competitor AS (
  SELECT
    b1.user_id,
    b1.perf_score_raw,
    (SELECT b2.user_id FROM bench b2
     WHERE b2.perf_score_raw > b1.perf_score_raw
     ORDER BY b2.perf_score_raw ASC
     LIMIT 1) AS next_higher_user,
    (SELECT MIN(b2.perf_score_raw - b1.perf_score_raw) FROM bench b2 WHERE b2.perf_score_raw > b1.perf_score_raw) AS points_to_next
  FROM bench b1
),
-- final selection assembled with outer joins, complex predicates and string expressions
final AS (
  SELECT
    b.user_id,
    b.display_name,
    COALESCE(u.Reputation,0) AS reputation,
    b.questions_posted,
    b.answers_posted,
    b.total_post_score,
    b.avg_nonzero_score,
    b.answers_given,
    b.top_tag,
    b.badge_total,
    b.gold_badges,
    b.silver_badges,
    b.bronze_badges,
    COALESCE(b.linked_post_exposure,0) AS linked_posts,
    COALESCE(b.edit_count,0) AS edit_count,
    COALESCE(am.avg_answer_hours, NULL) AS avg_answer_hours,
    COALESCE(am.accepted_count,0) AS accepted_answers,
    COALESCE(ub.distinct_badge_names, '') AS badge_names,
    COALESCE(nc.next_higher_user, -1) AS next_higher_user,
    COALESCE(nc.points_to_next, 0) AS points_to_next,
    b.perf_score_raw,
    b.perf_rank,
    b.score_decile,
    -- synthesized description with null handling and string ops
    (COALESCE(u.Location, '<unknown location>') || ' | ' || COALESCE(b.top_tag, '<no tag>') || CASE WHEN b.badge_total > 0 THEN ' | ' || COALESCE(split_part(ub.distinct_badge_names, ' | ', 1), ub.distinct_badge_names) ELSE '' END) AS short_profile,
    -- a boolean-like indicator using NULL logic
    CASE
      WHEN b.perf_score_raw IS NULL THEN 'unknown'
      WHEN b.perf_score_raw >= 50 THEN 'elite'
      WHEN b.perf_score_raw >= 20 THEN 'solid'
      WHEN b.perf_score_raw >= 5 THEN 'active'
      ELSE 'casual'
    END AS performance_tier
  FROM bench b
  LEFT JOIN Users u ON u.Id = b.user_id
  LEFT JOIN answer_metrics am ON am.user_id = b.user_id
  LEFT JOIN user_badges ub ON ub.user_id = b.user_id
  LEFT JOIN nearest_competitor nc ON nc.user_id = b.user_id
)
-- final ordering mixes window and complex predicate and includes a HAVING-like filter via WHERE
SELECT
  f.*,
  -- additional analytics: moving average of perf_score over rank neighborhood
  AVG(f.perf_score_raw) OVER (ORDER BY f.perf_rank ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) AS perf_score_moving_avg,
  LEAD(f.perf_score_raw) OVER (ORDER BY f.perf_rank) AS perf_score_next,
  LAG(f.perf_score_raw) OVER (ORDER BY f.perf_rank) AS perf_score_prev
FROM final f
WHERE
  -- only users who have at least some contribution or badges or recent activity OR exceptionally high reputation
  (f.questions_posted + f.answers_posted > 0 OR f.badge_total > 0 OR COALESCE(f.reputation,0) > 10000 OR f.perf_score_raw >= 5)
  -- exclude ghost users (display name unknown and zero everything)
  AND NOT (f.display_name = '<unknown>' AND f.questions_posted IS NULL AND f.answers_posted IS NULL)
ORDER BY
  f.perf_rank, f.reputation DESC
LIMIT 250;