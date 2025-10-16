-- {"query": "242.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4669} 
WITH
-- explode tags from Posts.Tags (questions only)
tags_exploded AS (
  SELECT
    p.id AS question_id,
    trim(both ' ' FROM tag) AS tag_name
  FROM Posts p
  CROSS JOIN LATERAL unnest(
    string_to_array(
      substring(p.Tags, 2, length(p.Tags) - 2),
      '><'
    )
  ) AS tag(tag)
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),

-- basic user aggregates derived from multiple sources (posts, comments, votes, badges)
user_post_aggregates AS (
  SELECT
    COALESCE(p.OwnerUserId, -1) AS user_id,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
    SUM(CASE WHEN p.PostTypeId IN (1,2) THEN COALESCE(p.Score,0) ELSE 0 END) AS total_post_score,
    AVG(NULLIF(p.Score,0)) FILTER (WHERE p.Score IS NOT NULL) AS avg_nonzero_score,
    MAX(p.Score) AS max_post_score,
    COUNT(p.Id) AS post_rows
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY COALESCE(p.OwnerUserId, -1)
),

user_comment_aggregates AS (
  SELECT
    COALESCE(c.UserId, -1) AS user_id,
    COUNT(*) FILTER (WHERE c.UserId IS NOT NULL) AS comment_count,
    SUM(COALESCE(c.Score,0)) AS comment_score_total
  FROM Comments c
  GROUP BY COALESCE(c.UserId, -1)
),

user_badge_aggregates AS (
  SELECT
    b.UserId AS user_id,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
    SUM(CASE WHEN b.TagBased = B'1' THEN 1 ELSE 0 END) AS tag_based_badges
  FROM Badges b
  GROUP BY b.UserId
),

-- combine user aggregates with full outer joins so users without posts or badges are included
user_activity AS (
  SELECT
    COALESCE(u.Id, upa.user_id, uca.user_id, uba.user_id) AS user_id,
    u.DisplayName,
    COALESCE(u.Reputation,0) AS reputation,
    COALESCE(upa.question_count,0) AS question_count,
    COALESCE(upa.answer_count,0) AS answer_count,
    COALESCE(upa.total_post_score,0) AS total_post_score,
    COALESCE(upa.avg_nonzero_score,0) AS avg_nonzero_score,
    COALESCE(upa.max_post_score,0) AS max_post_score,
    COALESCE(uca.comment_count,0) AS comment_count,
    COALESCE(uca.comment_score_total,0) AS comment_score_total,
    COALESCE(uba.gold_badges,0) AS gold_badges,
    COALESCE(uba.silver_badges,0) AS silver_badges,
    COALESCE(uba.bronze_badges,0) AS bronze_badges,
    COALESCE(uba.tag_based_badges,0) AS tag_based_badges,
    -- recent activity flag via correlated subquery
    CASE WHEN EXISTS (
      SELECT 1 FROM Posts p2
      WHERE p2.OwnerUserId = COALESCE(u.Id, upa.user_id)
        AND p2.LastActivityDate > (CURRENT_TIMESTAMP - INTERVAL '30 days')
      LIMIT 1
    ) THEN true ELSE false END AS recent_activity,
    u.CreationDate,
    u.LastAccessDate
  FROM Users u
  FULL OUTER JOIN user_post_aggregates upa ON u.Id = upa.user_id
  FULL OUTER JOIN user_comment_aggregates uca ON COALESCE(u.Id, upa.user_id) = uca.user_id
  FULL OUTER JOIN user_badge_aggregates uba ON COALESCE(u.Id, upa.user_id, uca.user_id) = uba.user_id
),

-- recent post history: latest revision per post
recent_post_history AS (
  SELECT ph.*
  FROM (
    SELECT ph.*,
           row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC NULLS LAST, ph.Id DESC) AS rn
    FROM PostHistory ph
  ) ph
  WHERE ph.rn = 1
),

-- per-question enriched stats including a correlated lateral subquery for top answer
question_stats AS (
  SELECT
    q.Id AS question_id,
    q.Title,
    q.OwnerUserId AS owner_user_id,
    q.Score AS question_score,
    q.ViewCount,
    q.CreationDate,
    q.AcceptedAnswerId,
    q.AnswerCount,
    -- aggregate tags as canonical string for the question
    COALESCE(
      (SELECT string_agg(distinct te.tag_name, ', ' ORDER BY min(te.tag_name))
       FROM tags_exploded te WHERE te.question_id = q.Id),
      '') AS tag_list,
    -- top answer by score (correlated lateral)
    ta.top_answer_id,
    ta.top_answer_score,
    -- days since creation (floored)
    FLOOR(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - q.CreationDate)) / 86400) AS days_since_creation,
    -- whether accepted answer is the top answer
    CASE WHEN q.AcceptedAnswerId IS NOT NULL AND q.AcceptedAnswerId = ta.top_answer_id THEN true ELSE false END AS accepted_is_top
  FROM Posts q
  LEFT JOIN LATERAL (
    SELECT a.Id AS top_answer_id, a.Score AS top_answer_score
    FROM Posts a
    WHERE a.ParentId = q.Id
    ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC
    LIMIT 1
  ) ta ON true
  WHERE q.PostTypeId = 1
),

-- leaders per tag: top 3 questions by score per tag using window functions
tag_leaders AS (
  SELECT
    t.tag_name,
    tl.qid,
    tl.title,
    tl.score,
    tl.viewcount,
    tl.days_since_creation,
    tl.rn
  FROM (
    SELECT
      te.tag_name,
      p.Id AS qid,
      p.Title AS title,
      COALESCE(p.Score,0) AS score,
      COALESCE(p.ViewCount,0) AS viewcount,
      FLOOR(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate))/86400) AS days_since_creation,
      row_number() OVER (PARTITION BY te.tag_name ORDER BY COALESCE(p.Score,0) DESC NULLS LAST, COALESCE(p.ViewCount,0) DESC) AS rn
    FROM tags_exploded te
    JOIN Posts p ON p.Id = te.question_id
    WHERE p.PostTypeId = 1
  ) tl
  WHERE tl.rn <= 3
),

-- set of active candidates: users with posts in last year or badges in last year (uses set operators)
active_candidates AS (
  SELECT DISTINCT u.Id AS user_id FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '365 days')
  UNION
  SELECT DISTINCT b.UserId FROM Badges b
  WHERE b.Date > (CURRENT_TIMESTAMP - INTERVAL '365 days')
),

-- compile a unified "entity" rowset mixing users and tags (for benchmarking variety) using UNION ALL
combined_entities AS (
  -- user rows
  SELECT
    'user'::text AS entity_type,
    ua.user_id::text AS entity_key,
    COALESCE(ua.DisplayName, CONCAT('user#', ua.user_id::text)) AS label,
    ua.reputation::bigint AS metric_a,
    (ua.question_count + ua.answer_count + ua.comment_count)::bigint AS metric_b,
    CONCAT(
      'Q=', ua.question_count, ';A=', ua.answer_count, ';C=', ua.comment_count,
      ';G=', ua.gold_badges, ';S=', ua.silver_badges, ';B=', ua.bronze_badges
    ) AS details,
    ua.recent_activity,
    ua.CreationDate
  FROM user_activity ua
  WHERE ua.user_id > 0

  UNION ALL

  -- tag rows: top aggregated stats per tag
  SELECT
    'tag'::text AS entity_type,
    COALESCE(t.Id::text, ('tag:' || tl.tag_name)) AS entity_key,
    COALESCE(t.TagName, tl.tag_name) AS label,
    COALESCE(t.Count, 0)::bigint AS metric_a,
    COALESCE(SUM(tl.score) OVER (PARTITION BY tl.tag_name), 0)::bigint AS metric_b,
    CONCAT(
      'TopQuestions=', string_agg(DISTINCT tl.title || ' (s=' || tl.score || ',v=' || tl.viewcount || ')', ' || ' ORDER BY tl.rn),
      ' -- top3count=', COUNT(*) FILTER (WHERE tl.rn <= 3)
    ) AS details,
    false AS recent_activity,
    NULL::timestamp AS CreationDate
  FROM tag_leaders tl
  LEFT JOIN Tags t ON t.TagName = tl.tag_name
  GROUP BY COALESCE(t.Id::text, ('tag:' || tl.tag_name)), COALESCE(t.TagName, tl.tag_name), t.Count
),

-- filter out low-value rows by set operator: keep combined_entities except those with metric_b = 0
filtered_entities AS (
  SELECT * FROM combined_entities
  EXCEPT
  SELECT * FROM combined_entities WHERE metric_b = 0
),

-- rank users by reputation and by combined metric, include some complex expressions and null logic
ranked_entities AS (
  SELECT
    fe.*,
    row_number() OVER (PARTITION BY fe.entity_type ORDER BY fe.metric_a DESC NULLS LAST, fe.metric_b DESC NULLS LAST) AS rank_within_type,
    dense_rank() OVER (ORDER BY COALESCE(fe.metric_a,0) + COALESCE(fe.metric_b,0) DESC) AS overall_dense_rank,
    -- synthetic score with NULL-safe math and weight decay by days since creation for users
    CASE
      WHEN fe.entity_type = 'user' THEN
        (COALESCE(fe.metric_a,0) * 0.6) + (COALESCE(fe.metric_b,0) * 0.3) + (CASE WHEN fe.recent_activity THEN 50 ELSE 0 END)
      ELSE
        (COALESCE(fe.metric_a,0) * 0.4) + (COALESCE(fe.metric_b,0) * 0.6)
    END AS synthetic_score,
    -- complex label normalization
    regexp_replace(lower(fe.label::text), '[\n\r\t]+', ' ', 'g') AS normalized_label
  FROM filtered_entities fe
)

-- final selection: mix of users and tags, use correlated subquery to attach a "sample post" snippet if user
SELECT
  re.entity_type,
  re.entity_key,
  re.label,
  re.normalized_label,
  re.metric_a,
  re.metric_b,
  re.synthetic_score,
  re.rank_within_type,
  re.overall_dense_rank,
  re.details,
  -- correlated subquery: for users, pick a representative recent post snippet (first 120 chars), for tags pick exemplar question title
  CASE
    WHEN re.entity_type = 'user' THEN (
      SELECT substring(p.Body FROM 1 FOR 120) || '...' FROM Posts p
      WHERE p.OwnerUserId::text = re.entity_key
      ORDER BY GREATEST(COALESCE(p.Score,0), COALESCE(p.ViewCount,0)) DESC NULLS LAST
      LIMIT 1
    )
    ELSE (
      SELECT substring(Title FROM 1 FOR 120) FROM Posts p
      WHERE p.Id = (
        SELECT qid FROM tag_leaders tl WHERE tl.tag_name = re.label LIMIT 1
      )
      LIMIT 1
    )
  END AS exemplar_snippet,
  -- boolean indicating whether this entity appears in active_candidates (users only; tags always false)
  CASE WHEN re.entity_type = 'user' THEN
    (re.entity_key::int IN (SELECT user_id FROM active_candidates))
  ELSE false END AS is_recent_candidate
FROM ranked_entities re
ORDER BY re.entity_type, re.rank_within_type ASC, re.synthetic_score DESC
LIMIT 200;