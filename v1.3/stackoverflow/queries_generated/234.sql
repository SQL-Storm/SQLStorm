-- {"query": "234.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3491} 
WITH
recent_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate
  FROM Users u
  WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
     OR u.Reputation >= 10000
),
answer_pool AS (
  SELECT a.*, a.ParentId AS QuestionId
  FROM Posts a
  WHERE a.PostTypeId = 2
),
ranked_answers AS (
  SELECT
    a.*,
    row_number() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(a.Score,0) DESC, a.CreationDate) AS ans_rank,
    dense_rank()  OVER (PARTITION BY a.ParentId ORDER BY COALESCE(a.Score,0) DESC)         AS ans_dr
  FROM answer_pool a
),
top_answers AS (
  SELECT *
  FROM ranked_answers
  WHERE ans_rank = 1
),
vote_agg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes,
    COUNT(*) AS total_votes,
    MAX(v.CreationDate) AS last_vote_at
  FROM Votes v
  GROUP BY v.PostId
),
history_agg AS (
  SELECT
    ph.PostId,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS close_events,  -- Post Closed
    SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS reopen_events,
    MAX(ph.CreationDate) AS last_history_at,
    bool_or(ph.PostHistoryTypeId = 50) AS bumped_by_community -- CommunityBump
  FROM PostHistory ph
  GROUP BY ph.PostId
),
tag_exploded AS (
  -- explode tags stored like '<tag1><tag2>' into rows; handle NULL/empty safely
  SELECT
    p.Id AS PostId,
    trim(t.tag) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(COALESCE(p.Tags,''), 2, GREATEST(length(COALESCE(p.Tags,'')) - 2,0)), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1 AND COALESCE(p.Tags,'') <> ''
),
tag_stats AS (
  SELECT
    te.tag,
    COUNT(*) AS questions_with_tag,
    AVG(q.Score) FILTER (WHERE q.Score IS NOT NULL) AS avg_question_score,
    AVG(q.ViewCount) FILTER (WHERE q.ViewCount IS NOT NULL) AS avg_views,
    MAX(q.ViewCount) AS max_views,
    SUM(q.AnswerCount) AS total_answers_for_tag
  FROM tag_exploded te
  JOIN Posts q ON q.Id = te.PostId
  GROUP BY te.tag
),
problematic_questions AS (
  -- union of several brittle/controversial sets, minus trivial exclusions
  (SELECT q.Id
   FROM Posts q
   LEFT JOIN history_agg h ON h.PostId = q.Id
   WHERE q.PostTypeId = 1
     AND (COALESCE(h.close_events,0) >= 2 OR COALESCE(q.Score,0) <= -2)
     AND COALESCE(q.ViewCount,0) < 1000)
  UNION
  (SELECT q.Id
   FROM Posts q
   WHERE q.PostTypeId = 1
     AND (q.LastActivityDate IS NOT NULL AND q.LastActivityDate < CURRENT_TIMESTAMP - INTERVAL '5 years'))
  EXCEPT
  (SELECT p.Id FROM Posts p WHERE p.FavoriteCount IS NOT NULL AND p.FavoriteCount > 10)
),
question_core AS (
  SELECT
    q.Id,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    q.OwnerUserId,
    q.Tags,
    u.DisplayName AS OwnerName,
    u.Reputation AS OwnerReputation,
    COALESCE(v.upvotes,0) AS upvotes,
    COALESCE(v.downvotes,0) AS downvotes,
    COALESCE(h.close_events,0) AS close_events,
    COALESCE(h.reopen_events,0) AS reopen_events,
    COALESCE(h.bumped_by_community, false) AS bumped,
    CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS has_accepted,
    -- correlated subqueries:
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS real_answer_count,
    (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS first_answer_at,
    (SELECT COUNT(DISTINCT a.OwnerUserId) FROM Posts a WHERE a.ParentId = q.Id AND a.OwnerUserId IS NOT NULL) AS distinct_answerers,
    (SELECT c.Text FROM Comments c WHERE c.PostId = q.Id ORDER BY c.CreationDate DESC LIMIT 1) AS last_comment_text,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS comment_count,
    (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = q.Id AND vv.VoteTypeId = 6) AS close_vote_records  -- existing stored close votes (rare)
  FROM Posts q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN vote_agg v ON v.PostId = q.Id
  LEFT JOIN history_agg h ON h.PostId = q.Id
  WHERE q.PostTypeId = 1
),
question_tag_matrix AS (
  -- attach one tag per question per row (many-to-many), plus a concatenated tag summary
  SELECT
    qc.*,
    te.tag,
    -- compact tag list: top 5 tags only
    (SELECT string_agg(t2.tag, ', ' ORDER BY tag_stats.questions_with_tag DESC NULLS LAST, t2.tag)
     FROM (
       SELECT DISTINCT trim(t.tag) AS tag
       FROM Posts p2
       CROSS JOIN LATERAL (
         SELECT unnest(string_to_array(substring(COALESCE(p2.Tags,''), 2, GREATEST(length(COALESCE(p2.Tags,'')) - 2,0)), '><')) AS tag
       ) t
       WHERE p2.Id = qc.Id
       LIMIT 5
     ) t2
    ) AS tag_summary
  FROM question_core qc
  LEFT JOIN tag_exploded te ON te.PostId = qc.Id
),
composite_scores AS (
  SELECT
    qtm.*,
    -- composite scoring formula with NULL logic, logs and dampening
    (COALESCE(qtm.Score,0)::numeric * 1.8)
    + (COALESCE(qtm.upvotes,0)::numeric * 2.2)
    - (COALESCE(qtm.downvotes,0)::numeric * 1.3)
    + (CASE WHEN qtm.has_accepted = 1 THEN 75 ELSE 0 END)
    + (COALESCE(LOG(1 + NULLIF(qtm.ViewCount,0)::numeric), 0) * 6)
    + (COALESCE(qtm.real_answer_count,0) * 3)
    - (COALESCE(qtm.close_events,0) * 8)
    + (CASE WHEN qtm.bumped THEN 5 ELSE 0 END)
    - (CASE WHEN qtm.first_answer_at IS NULL THEN 12 ELSE EXTRACT(EPOCH FROM (qtm.first_answer_at - qtm.CreationDate))/86400 END) / 10.0
    + (COALESCE(qtm.distinct_answerers,0) * 1.1)
    AS composite_score,
    -- recency and activity window metrics
    row_number() OVER (ORDER BY
       (COALESCE(qtm.Score,0) * 1.2 + COALESCE(qtm.upvotes,0) - COALESCE(qtm.downvotes,0))
       DESC, qtm.CreationDate DESC) AS global_rank,
    rank() OVER (PARTITION BY qtm.tag ORDER BY COALESCE(qtm.Score,0) DESC NULLS LAST) AS rank_in_tag
  FROM question_tag_matrix qtm
),
final_selection AS (
  SELECT
    cs.Id AS question_id,
    COALESCE(cs.Title, '[no title]') AS title_snippet,
    LEFT(COALESCE(cs.title, ''), 180) || CASE WHEN LENGTH(COALESCE(cs.title,'')) > 180 THEN '...' ELSE '' END AS title_trunc,
    COALESCE(cs.OwnerName, '[deleted]') AS owner,
    cs.OwnerReputation,
    cs.tag_summary,
    cs.tag,
    cs.Score,
    cs.ViewCount,
    cs.real_answer_count,
    cs.distinct_answerers,
    cs.comment_count,
    cs.close_events,
    cs.has_accepted,
    cs.first_answer_at,
    cs.last_comment_text,
    cs.composite_score,
    cs.global_rank,
    cs.rank_in_tag,
    -- bring in accepted answer summary via left join
    ta.Id AS accepted_answer_id,
    ta.Score AS accepted_answer_score,
    ta.OwnerUserId AS accepted_answer_owner,
    -- include aggregated votes and last vote time
    v.upvotes AS aggregated_upvotes,
    v.downvotes AS aggregated_downvotes,
    v.last_vote_at,
    -- flag if problematic and a final sanity flag using EXISTS correlated subquery
    CASE WHEN EXISTS (SELECT 1 FROM problematic_questions pq WHERE pq.Id = cs.Id) THEN true ELSE false END AS is_problematic,
    -- descriptive short URL-like slug synthesized from title + id
    LOWER(regexp_replace(COALESCE(cs.Title,''),'[^a-zA-Z0-9]+','-','g')) || '-' || cs.Id::text AS synthetic_slug
  FROM composite_scores cs
  LEFT JOIN Posts ta ON ta.Id = cs.AcceptedAnswerId
  LEFT JOIN vote_agg v ON v.PostId = cs.Id
)
SELECT *
FROM final_selection
WHERE (composite_score IS NOT NULL AND composite_score > 5)
  AND (OwnerReputation IS NULL OR OwnerReputation > 50 OR is_problematic = true)
ORDER BY composite_score DESC NULLS LAST, ViewCount DESC
LIMIT 100;