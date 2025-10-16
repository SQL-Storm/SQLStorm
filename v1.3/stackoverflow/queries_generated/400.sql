-- {"query": "400.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18188} 
WITH
user_posts AS (
  SELECT u.Id AS user_id,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
         COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
         AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS avg_q_score,
         AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_a_score,
         SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount,0) ELSE 0 END) AS question_views,
         MAX(p.LastActivityDate) AS last_activity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
user_badges AS (
  SELECT b.UserId,
         COUNT(*) AS total_badges,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
         SUM(CASE WHEN b.TagBased = B'1' THEN 1 ELSE 0 END) AS tag_based
  FROM Badges b
  GROUP BY b.UserId
),
exploded_tags AS (
  SELECT p.Id AS post_id,
         p.OwnerUserId AS owner_user_id,
         TRIM(t) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
tag_stats AS (
  SELECT et.tag,
         COUNT(*) AS q_count,
         AVG(p.Score) AS avg_score,
         AVG(p.ViewCount) AS avg_views,
         COUNT(DISTINCT et.owner_user_id) AS distinct_askers,
         SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS closed_count,
         MIN(p.CreationDate) AS first_seen,
         MAX(p.CreationDate) AS last_seen
  FROM exploded_tags et
  JOIN Posts p ON p.Id = et.post_id
  GROUP BY et.tag
),
top_answerers_per_tag AS (
  SELECT tag, answerer_id, answers_for_tag, ROW_NUMBER() OVER (PARTITION BY tag ORDER BY answers_for_tag DESC) AS rn
  FROM (
    SELECT et.tag, a.OwnerUserId AS answerer_id, COUNT(*) AS answers_for_tag
    FROM exploded_tags et
    JOIN Posts q ON q.Id = et.post_id
    JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE a.OwnerUserId IS NOT NULL
    GROUP BY et.tag, a.OwnerUserId
  ) t
),
post_vote_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_by_originator,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorite_count,
         COUNT(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
post_history_agg AS (
  SELECT ph.PostId,
         COUNT(*) AS history_events,
         SUM(CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13,35,36) THEN 1 ELSE 0 END) AS close_reopen_related,
         MAX(ph.CreationDate) AS last_history_date
  FROM PostHistory ph
  GROUP BY ph.PostId
),
user_tag_metrics AS (
  SELECT u.Id AS user_id,
         COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
         COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
         COUNT(et.tag) AS total_tagged_questions,
         MAX(et.tag) FILTER (WHERE et.tag IS NOT NULL) AS sample_tag,
         (
           SELECT ttag FROM (
             SELECT et2.tag AS ttag, COUNT(*) AS cnt
             FROM exploded_tags et2
             JOIN Posts q2 ON q2.Id = et2.post_id
             WHERE q2.OwnerUserId = u.Id
             GROUP BY et2.tag
             ORDER BY cnt DESC NULLS LAST
             LIMIT 1
           ) sub
         ) AS top_tag
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN exploded_tags et ON et.post_id = p.Id AND p.PostTypeId = 1
  GROUP BY u.Id
),
user_rankings AS (
  SELECT up.*,
         COALESCE(ub.total_badges,0) AS total_badges,
         COALESCE(ub.gold,0) AS gold,
         COALESCE(ub.silver,0) AS silver,
         COALESCE(ub.bronze,0) AS bronze,
         ROW_NUMBER() OVER (ORDER BY up.Reputation DESC NULLS LAST, up.questions DESC NULLS LAST) AS rep_rank,
         RANK() OVER (ORDER BY up.questions DESC NULLS LAST) AS q_rank,
         PERCENT_RANK() OVER (ORDER BY up.Reputation) AS rep_pct
  FROM user_posts up
  LEFT JOIN user_badges ub ON ub.UserId = up.user_id
),
tag_with_topanswer AS (
  SELECT ts.*,
         ta.answerer_id AS top_answerer,
         ta.answers_for_tag
  FROM tag_stats ts
  LEFT JOIN (
    SELECT tag, answerer_id, answers_for_tag FROM top_answerers_per_tag WHERE rn = 1
  ) ta ON ta.tag = ts.tag
),
user_complex AS (
  SELECT ur.user_id,
         ur.DisplayName,
         ur.Reputation,
         ur.questions,
         ur.answers,
         ur.question_views,
         ur.avg_q_score,
         ur.avg_a_score,
         ur.last_activity,
         ur.rep_rank,
         ur.q_rank,
         ur.rep_pct,
         ur.total_badges,
         ur.gold,
         ur.silver,
         ur.bronze,
         utm.top_tag AS top_tag,
         CASE WHEN (ur.questions + ur.answers) = 0 THEN 0 ELSE
              (COALESCE(ur.avg_q_score,0) * ur.questions + COALESCE(ur.avg_a_score,0) * ur.answers) / NULLIF((ur.questions + ur.answers),0)
         END AS weighted_score,
         (SELECT COUNT(*) FROM PostLinks pl JOIN Posts rp ON rp.Id = pl.RelatedPostId WHERE rp.OwnerUserId = ur.user_id AND pl.LinkTypeId = 3) AS duplicates_against,
         (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = ur.user_id AND ph.PostHistoryTypeId IN (10,11,12,13,35,36)) AS history_close_related,
         (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ur.user_id AND c.CreationDate > now() - interval '180 days') AS comments_last_180d,
         (ur.Reputation - AVG(ur.Reputation) OVER ()) / NULLIF(STDDEV_POP(ur.Reputation) OVER (),0) AS rep_zscore
  FROM user_rankings ur
  LEFT JOIN user_tag_metrics utm ON utm.user_id = ur.user_id
)
(
  SELECT
    'USER' AS row_type,
    uc.user_id::text AS id,
    COALESCE(uc.DisplayName, '(deleted)') AS name,
    uc.Reputation,
    uc.rep_rank,
    uc.q_rank,
    uc.rep_pct,
    uc.questions,
    uc.answers,
    uc.question_views,
    uc.avg_q_score,
    uc.avg_a_score,
    uc.weighted_score,
    uc.total_badges,
    uc.gold,
    uc.silver,
    uc.bronze,
    COALESCE(twa.tag, uc.top_tag, '(none)') AS prominent_tag,
    twa.q_count AS prominent_tag_q_count,
    twa.avg_score AS prominent_tag_avg_score,
    twa.avg_views AS prominent_tag_avg_views,
    (SELECT u2.DisplayName FROM Users u2 WHERE u2.Id = twa.top_answerer) AS prominent_tag_top_answerer_name,
    uc.duplicates_against,
    uc.history_close_related,
    uc.comments_last_180d,
    uc.rep_zscore,
    CASE WHEN uc.questions > 0 AND uc.answers >= 2 * uc.questions THEN 'Power Answerer'
         WHEN uc.answers > 0 AND uc.questions >= 2 * uc.answers THEN 'Power Asker'
         WHEN uc.questions = 0 AND uc.answers = 0 THEN 'Lurker'
         ELSE 'Balanced'
    END AS archetype,
    CONCAT(COALESCE(uc.DisplayName,'(deleted)'), ' <', COALESCE(uc.top_tag,'none'), '>') AS name_tag_combo
  FROM user_complex uc
  LEFT JOIN LATERAL (
    SELECT * FROM tag_with_topanswer t WHERE t.tag = uc.top_tag ORDER BY t.q_count DESC LIMIT 1
  ) twa ON TRUE
  WHERE (uc.Reputation > (SELECT AVG(Reputation) FROM Users) AND (uc.questions > 0 OR uc.answers > 0))
    AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = uc.user_id AND b.Name ILIKE '%moderator%')
  ORDER BY uc.rep_rank
  LIMIT 100
)
UNION ALL
(
  SELECT
    'TAG' AS row_type,
    ts.tag::text AS id,
    ts.tag::text AS name,
    NULL::int AS Reputation,
    NULL::int AS rep_rank,
    NULL::int AS q_rank,
    NULL::float AS rep_pct,
    ts.q_count::int AS questions,
    NULL::int AS answers,
    COALESCE(ROUND(ts.avg_views)::int,0) AS question_views,
    COALESCE(ts.avg_score,0.0) AS avg_q_score,
    NULL::float AS avg_a_score,
    COALESCE((COALESCE(ts.avg_score,0.0) * ts.q_count)::float / NULLIF(ts.q_count,0),0.0) AS weighted_score,
    NULL::int AS total_badges,
    NULL::int AS gold,
    NULL::int AS silver,
    NULL::int AS bronze,
    ts.tag::text AS prominent_tag,
    ts.q_count::int AS prominent_tag_q_count,
    COALESCE(ts.avg_score,0.0) AS prominent_tag_avg_score,
    COALESCE(ts.avg_views,0.0) AS prominent_tag_avg_views,
    (SELECT u.DisplayName FROM Users u WHERE u.Id = ts.top_answerer) AS prominent_tag_top_answerer_name,
    NULL::int AS duplicates_against,
    NULL::int AS history_close_related,
    NULL::int AS comments_last_180d,
    NULL::float AS rep_zscore,
    'TAG_SUMMARY'::text AS archetype,
    CONCAT(ts.tag,' (', COALESCE(ts.q_count::text,'0'), ' q)')::text AS name_tag_combo
  FROM tag_with_topanswer ts
  ORDER BY ts.q_count DESC
  LIMIT 20
)
ORDER BY row_type DESC, questions DESC, rep_rank ASC;