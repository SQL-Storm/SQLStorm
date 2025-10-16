-- {"query": "298.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4048} 
WITH
q AS (
  SELECT
    p.*,
    COALESCE(p.Tags, '') AS raw_tags,
    CASE WHEN p.Tags IS NULL THEN ARRAY[]::text[] ELSE string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') END AS tag_array
  FROM Posts p
  WHERE p.PostTypeId = 1
),
answers AS (
  SELECT
    a.ParentId AS question_id,
    count(*) AS answer_count,
    avg(a.Score)::numeric(10,2) AS answer_avg_score,
    max(a.Score) AS answer_max_score,
    bool_or(a.Id = q.AcceptedAnswerId) AS has_accepted_answer -- will be NULL if q row unavailable here; used later by join
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
votes_by_post AS (
  SELECT
    PostId,
    sum(case when VoteTypeId = 2 then 1 else 0 end) AS upvotes,
    sum(case when VoteTypeId = 3 then 1 else 0 end) AS downvotes,
    sum(1) AS total_votes
  FROM Votes
  GROUP BY PostId
),
user_badges AS (
  SELECT
    UserId,
    count(*) AS badge_count,
    sum(case when Class = 1 then 5 when Class = 2 then 3 else 1 end)::numeric(10,2) AS badge_weight,
    max(Date) AS last_badge_date
  FROM Badges
  GROUP BY UserId
),
recent_activity AS (
  SELECT
    p.Id AS post_id,
    greatest(max(ph.CreationDate), p.LastActivityDate, p.LastEditDate, p.LastEditDate) AS last_activity
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  GROUP BY p.Id, p.LastActivityDate, p.LastEditDate
),
tag_exploded AS (
  SELECT
    q.Id AS question_id,
    t.tag,
    t.ord
  FROM q
  CROSS JOIN LATERAL unnest(q.tag_array) WITH ORDINALITY AS t(tag, ord)
),
tag_with_meta AS (
  SELECT
    te.*,
    tg.Count AS tag_popularity
  FROM tag_exploded te
  LEFT JOIN Tags tg ON tg.TagName = te.tag
),
tag_rank AS (
  SELECT
    question_id,
    string_agg(tag, ',' ORDER BY ord) AS tags_ordered,
    max(coalesce(tag_popularity,0)) AS max_tag_popularity,
    min(coalesce(tag_popularity,0)) AS min_tag_popularity,
    count(*) AS tag_count
  FROM tag_with_meta
  GROUP BY question_id
),
duplicate_links AS (
  SELECT pl.PostId AS duplicate_of, pl.RelatedPostId AS master_of, pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
),
recent_commenters AS (
  SELECT
    c.PostId,
    count(DISTINCT c.UserId) FILTER (WHERE c.UserId IS NOT NULL) AS distinct_commenters,
    count(*) FILTER (WHERE c.CreationDate > now() - interval '30 days') AS comments_last_30_days
  FROM Comments c
  GROUP BY c.PostId
),
-- Compute per-owner ranking windows and global hotness
enriched AS (
  SELECT
    q.*,
    coalesce(a.answer_count,0) AS answer_count,
    a.answer_avg_score,
    a.answer_max_score,
    COALESCE(v.upvotes,0) AS upvotes,
    COALESCE(v.downvotes,0) AS downvotes,
    COALESCE(v.total_votes,0) AS total_votes,
    COALESCE(ub.badge_count,0) AS owner_badge_count,
    COALESCE(ub.badge_weight,0) AS owner_badge_weight,
    tr.tags_ordered,
    tr.tag_count,
    tr.max_tag_popularity,
    ra.last_activity,
    rc.distinct_commenters,
    rc.comments_last_30_days,
    dq.master_of IS NOT NULL AS is_duplicate_of,
    dq.duplicate_of,
    -- correlated subquery: hours until accepted answer (NULL if none)
    (SELECT EXTRACT(EPOCH FROM (a2.CreationDate - q.CreationDate))/3600.0
     FROM Posts a2
     WHERE a2.Id = q.AcceptedAnswerId
     LIMIT 1) AS accepted_latency_hours,
    -- correlated subquery: count of distinct answerers with reputation > owner's
    (SELECT count(DISTINCT ans.OwnerUserId)
     FROM Posts ans
     WHERE ans.ParentId = q.Id AND ans.OwnerUserId IS NOT NULL
       AND ans.OwnerUserId <> q.OwnerUserId
       AND (SELECT Reputation FROM Users u WHERE u.Id = ans.OwnerUserId) >
           COALESCE((SELECT Reputation FROM Users u2 WHERE u2.Id = q.OwnerUserId), 0)
    ) AS stronger_answerers_count
  FROM q
  LEFT JOIN answers a ON a.question_id = q.Id
  LEFT JOIN votes_by_post v ON v.PostId = q.Id
  LEFT JOIN user_badges ub ON ub.UserId = q.OwnerUserId
  LEFT JOIN tag_rank tr ON tr.question_id = q.Id
  LEFT JOIN recent_activity ra ON ra.post_id = q.Id
  LEFT JOIN recent_commenters rc ON rc.PostId = q.Id
  LEFT JOIN duplicate_links dq ON dq.duplicate_of = q.Id
)
SELECT
  e.Id AS question_id,
  coalesce(e.Title, '(no title)') AS title,
  coalesce(e.OwnerUserId, -1) AS owner_user_id,
  coalesce((SELECT DisplayName FROM Users u WHERE u.Id = e.OwnerUserId), e.OwnerDisplayName, 'unknown') AS owner_display,
  e.CreationDate,
  e.last_activity,
  e.Score,
  e.ViewCount,
  e.answer_count,
  e.answer_avg_score,
  e.answer_max_score,
  e.upvotes,
  e.downvotes,
  e.total_votes,
  e.owner_badge_count,
  e.owner_badge_weight,
  e.tags_ordered,
  e.tag_count,
  e.max_tag_popularity,
  e.min_tag_popularity,
  e.distinct_commenters,
  e.comments_last_30_days,
  e.is_duplicate_of,
  e.accepted_latency_hours,
  e.stronger_answerers_count,
  -- complex computed metric using NULL logic, math, and string operations
  round(
    (
      COALESCE(e.answer_count,0) * 1.75
      + (COALESCE(e.upvotes,0) - COALESCE(e.downvotes,0)) * 0.25
      + COALESCE(e.owner_badge_weight,0) * 0.4
      + ln(GREATEST(NULLIF(e.ViewCount,0),1)::numeric + 1) * 0.6
      - (CASE WHEN e.is_duplicate_of THEN 5 ELSE 0 END)
    )::numeric, 4
  ) AS engagement_score,
  -- window functions for per-owner rank and global hotness
  dense_rank() OVER (PARTITION BY e.OwnerUserId ORDER BY e.Score DESC NULLS LAST) AS rank_within_owner,
  row_number() OVER (ORDER BY (COALESCE(e.upvotes,0) - COALESCE(e.downvotes,0)) DESC, e.ViewCount DESC NULLS LAST) AS global_hot_rank,
  -- string gymnastics: short summary of title + tags
  left(replace(coalesce(e.Title,''), E'\n', ' '), 120) ||
    ' [{' || coalesce(e.tags_ordered, '') || '}]' AS short_summary
FROM enriched e
WHERE
  -- complicated predicate: recent or highly-engaged or contains 'sql' tag (case-insensitive)
  (
    e.last_activity > now() - interval '90 days'
    OR e.ViewCount > 10000
    OR EXISTS (
      SELECT 1 FROM tag_with_meta twm WHERE twm.question_id = e.Id AND lower(twm.tag) = 'sql'
    )
  )
  -- exclude closed/very old low-score noise using NULL-aware logic
  AND NOT (
    e.ClosedDate IS NOT NULL
    AND COALESCE(e.Score,0) < 0
    AND e.CreationDate < now() - interval '5 years'
  )
ORDER BY engagement_score DESC NULLS LAST, global_hot_rank
UNION ALL
-- Append a single summary row produced via aggregation using set operator
SELECT
  NULL::int AS question_id,
  'SUMMARY' AS title,
  NULL::int AS owner_user_id,
  NULL::varchar AS owner_display,
  NULL::timestamp AS CreationDate,
  NULL::timestamp AS last_activity,
  NULL::int AS Score,
  NULL::int AS ViewCount,
  sum(e.answer_count)::int AS answer_count,
  NULL::numeric AS answer_avg_score,
  NULL::int AS answer_max_score,
  sum(e.upvotes)::int AS upvotes,
  sum(e.downvotes)::int AS downvotes,
  sum(e.total_votes)::int AS total_votes,
  NULL::int AS owner_badge_count,
  NULL::numeric AS owner_badge_weight,
  NULL::text AS tags_ordered,
  NULL::int AS tag_count,
  NULL::int AS max_tag_popularity,
  NULL::int AS min_tag_popularity,
  NULL::int AS distinct_commenters,
  NULL::int AS comments_last_30_days,
  NULL::boolean AS is_duplicate_of,
  NULL::double precision AS accepted_latency_hours,
  NULL::int AS stronger_answerers_count,
  round(avg(
    (
      COALESCE(e.answer_count,0) * 1.75
      + (COALESCE(e.upvotes,0) - COALESCE(e.downvotes,0)) * 0.25
      + COALESCE(e.owner_badge_weight,0) * 0.4
      + ln(GREATEST(NULLIF(e.ViewCount,0),1)::numeric + 1) * 0.6
      - (CASE WHEN e.is_duplicate_of THEN 5 ELSE 0 END)
    )::numeric
  )::numeric, 4) AS engagement_score,
  NULL::int AS rank_within_owner,
  NULL::int AS global_hot_rank,
  'aggregate'::text AS short_summary
FROM enriched e
WHERE e.last_activity IS NOT NULL;