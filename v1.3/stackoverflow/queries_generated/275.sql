-- {"query": "275.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4042} 
WITH
-- recent questions within last year (or all if CreationDate is null)
recent_q AS (
  SELECT p.*, u.DisplayName AS OwnerName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND (p.CreationDate IS NULL OR p.CreationDate >= now() - INTERVAL '365 days')
),
-- explode tags like '<sql><postgres>' -> rows: 'sql', 'postgres'
tag_exploded AS (
  SELECT rq.Id AS QuestionId,
         lower(trim(both ' ' FROM tag)) AS tag
  FROM recent_q rq
  CROSS JOIN LATERAL (
    SELECT regexp_split_to_table(
             COALESCE(substring(rq.Tags, 2, greatest(length(rq.Tags) - 2,0)), ''),
             '><'
           ) AS tag
  ) s
  WHERE rq.Tags IS NOT NULL AND length(rq.Tags) > 2
),
-- per-tag statistics among recent questions
tag_stats AS (
  SELECT te.tag,
         count(*)                                  AS q_count,
         avg(rq.ViewCount)::numeric(18,2)          AS avg_views,
         max(rq.Score)                             AS max_score,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY rq.ViewCount) AS median_views
  FROM tag_exploded te
  JOIN recent_q rq ON rq.Id = te.QuestionId
  GROUP BY te.tag
),
-- aggregates of votes per post
vote_aggs AS (
  SELECT v.PostId,
         sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)  AS upvotes,
         sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)  AS downvotes,
         sum(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END)  AS accepted_flag,
         sum(CASE WHEN v.VoteTypeId IN (8,9) THEN coalesce(v.BountyAmount,0) ELSE 0 END) AS bounty_total,
         count(*)                                           AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
-- answer summaries per question (correlated info, also compute time to first answer)
answer_summary AS (
  SELECT q.Id AS QuestionId,
         count(a.Id) FILTER (WHERE a.Id IS NOT NULL)       AS answer_count,
         avg(a.Score) FILTER (WHERE a.Id IS NOT NULL)::numeric(18,3) AS avg_answer_score,
         max(a.Score) FILTER (WHERE a.Id IS NOT NULL)      AS best_answer_score,
         min(a.CreationDate) FILTER (WHERE a.Id IS NOT NULL) AS first_answer_time,
         -- time in hours to first answer (NULL-safe)
         EXTRACT(EPOCH FROM (min(a.CreationDate) - q.CreationDate))/3600.0 AS hours_to_first_answer
  FROM recent_q q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  GROUP BY q.Id
),
-- comments per post
comment_aggs AS (
  SELECT c.PostId,
         count(*) AS comment_count,
         sum(CASE WHEN c.UserId IS NULL THEN 0 ELSE 1 END) AS comments_by_registered
  FROM Comments c
  GROUP BY c.PostId
),
-- links out / duplicates
link_aggs AS (
  SELECT pl.PostId,
         count(*) FILTER (WHERE lt.Name = 'Linked' OR pl.LinkTypeId = 1) AS links_out,
         count(*) FILTER (WHERE pl.LinkTypeId = 3 OR lt.Name = 'Duplicate') AS duplicates_marked
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
-- recent edit history features (distinct editors, edit count, last edit info)
history_aggs AS (
  SELECT ph.PostId,
         count(*) AS revisions,
         count(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS distinct_editors,
         max(ph.CreationDate) AS last_edit_date,
         (string_agg(DISTINCT coalesce(u.DisplayName,'<anon>') || ':' || ph.PostHistoryTypeId::text, ',')) AS editor_types_sample
  FROM PostHistory ph
  LEFT JOIN Users u ON ph.UserId = u.Id
  GROUP BY ph.PostId
),
-- badge counts per user (for owner profile enrichment)
badge_summary AS (
  SELECT b.UserId,
         count(*) FILTER (WHERE b.Class = 1) AS gold_badges,
         count(*) FILTER (WHERE b.Class = 2) AS silver_badges,
         count(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
         count(*) AS total_badges
  FROM Badges b
  GROUP BY b.UserId
),
-- user aggregated activity
user_summary AS (
  SELECT u.Id,
         u.Reputation,
         u.CreationDate,
         u.Views AS profile_views,
         coalesce(b.gold_badges,0) AS gold_badges,
         coalesce(b.silver_badges,0) AS silver_badges,
         coalesce(b.bronze_badges,0) AS bronze_badges,
         -- activity score heuristic
         (u.Reputation * 0.6 + coalesce(u.Views,0) * 0.01 + coalesce(b.total_badges,0) * 10)::numeric(18,2) AS activity_score
  FROM Users u
  LEFT JOIN badge_summary b ON u.Id = b.UserId
),
-- top 3 answers per question as json-ish concatenation (uses posts table)
top_answers AS (
  SELECT a.ParentId AS QuestionId,
         string_agg(a.Id::text || ':' || coalesce(a.OwnerUserId::text,'-') || ':' || coalesce(a.Score::text,'0'), '|' ORDER BY a.Score DESC, a.CreationDate) AS top_answers_sample
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
-- entity hub mixing top tags and top users (SET operator demonstration)
entity_hub AS (
  SELECT tag AS name, 'tag' AS kind, q_count AS weight
  FROM tag_stats
  WHERE q_count >= 3
  UNION
  SELECT DisplayName AS name, 'user' AS kind, Reputation AS weight
  FROM Users
  WHERE DisplayName IS NOT NULL AND Reputation >= 1000
),
-- compute per-question combined metrics, ranks, and some correlated subqueries
question_full AS (
  SELECT q.Id,
         q.Title,
         q.CreationDate,
         q.ViewCount,
         q.Score,
         coalesce(va.upvotes,0) AS upvotes,
         coalesce(va.downvotes,0) AS downvotes,
         coalesce(va.bounty_total,0) AS bounty_total,
         coalesce(asum.answer_count,0) AS answer_count,
         coalesce(asum.hours_to_first_answer, NULL) AS hours_to_first_answer,
         coalesce(ca.comment_count,0) AS comment_count,
         coalesce(la.links_out,0) AS links_out,
         coalesce(la.duplicates_marked,0) AS duplicates_marked,
         hs.last_edit_date,
         hs.revisions,
         hs.distinct_editors,
         ua.activity_score AS owner_activity_score,
         ua.gold_badges,
         ua.silver_badges,
         ua.bronze_badges,
         ta.top_answers_sample,
         -- concatenated tag list (distinct) for the question
         (
           SELECT string_agg(distinct te.tag, ',' ORDER BY count_order) FROM (
             SELECT te.tag, row_number() OVER (PARTITION BY te.tag ORDER BY te.tag) AS count_order
             FROM tag_exploded te
             WHERE te.QuestionId = q.Id
           ) te
         ) AS tags_list,
         -- check if this question was ever closed via PostHistory (type 10)
         EXISTS (
           SELECT 1 FROM PostHistory ph
           WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10
         ) AS ever_closed,
         -- correlated subquery: accepted answer age in hours
         CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN
           (SELECT EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 FROM Posts a WHERE a.Id = q.AcceptedAnswerId)
         ELSE NULL END AS hours_to_accepted_answer,
         -- textual complexity metric: ratio of body length to title length (NULL-safe)
         CASE WHEN coalesce(length(q.Title),0) = 0 THEN NULL
              ELSE round( (length(coalesce(q.Body,''))::numeric / NULLIF(length(q.Title),0)) , 3)
         END AS body_title_complexity,
         -- composite hotness score (heuristic) includes recency, views, score, answers, owner activity, weighted and null-safe
         (
           coalesce(q.ViewCount,0)::numeric * 0.001
           + coalesce(q.Score,0) * 2
           + coalesce(asum.answer_count,0) * 3
           + coalesce(va.bounty_total,0) * 0.8
           + coalesce(ua.activity_score,0) * 0.01
           - coalesce(va.downvotes,0) * 0.5
           + CASE WHEN q.LastActivityDate IS NOT NULL THEN 10 / (1 + EXTRACT(EPOCH FROM (now() - q.LastActivityDate))/86400.0) ELSE 0 END
         )::numeric(18,4) AS hotness_score
  FROM recent_q q
  LEFT JOIN vote_aggs va ON va.PostId = q.Id
  LEFT JOIN answer_summary asum ON asum.QuestionId = q.Id
  LEFT JOIN comment_aggs ca ON ca.PostId = q.Id
  LEFT JOIN link_aggs la ON la.PostId = q.Id
  LEFT JOIN history_aggs hs ON hs.PostId = q.Id
  LEFT JOIN user_summary ua ON ua.Id = q.OwnerUserId
  LEFT JOIN top_answers ta ON ta.QuestionId = q.Id
),
-- rank questions within each tag by hotness (window functions)
tagged_ranked AS (
  SELECT qf.*,
         te.tag,
         row_number() OVER (PARTITION BY te.tag ORDER BY qf.hotness_score DESC NULLS LAST) AS rank_within_tag,
         dense_rank() OVER (ORDER BY qf.hotness_score DESC NULLS LAST) AS global_rank
  FROM question_full qf
  LEFT JOIN tag_exploded te ON te.QuestionId = qf.Id
),
-- pick only top N per tag and filter out synthetic tags (example of complicated predicate)
tag_top AS (
  SELECT *
  FROM tagged_ranked tr
  WHERE tr.rank_within_tag <= 5
    AND tr.tag IS NOT NULL
    AND length(tr.tag) BETWEEN 2 AND 35
    AND tr.tag !~ '(^[0-9]+$)'  -- exclude pure-numeric tags
),
-- final aggregation combining different perspectives with set operators and EXCEPT to remove low-interest items
final_candidates AS (
  SELECT 'question' AS entity_type, Id::text AS entity_id, Title AS label, hotness_score, tags_list, tag, rank_within_tag, global_rank
  FROM tag_top
  WHERE hotness_score IS NOT NULL
  UNION
  SELECT kind AS entity_type, name AS entity_id, name AS label, weight::numeric AS hotness_score, NULL::text AS tags_list, NULL::text AS tag, NULL::int AS rank_within_tag, NULL::int AS global_rank
  FROM entity_hub
  EXCEPT
  SELECT entity_type, entity_id, label, hotness_score, tags_list, tag, rank_within_tag, global_rank
  FROM (
    -- remove any entity that is trivial (very low weight or low hotness) - set subtraction example
    SELECT 'user' AS entity_type, DisplayName::text AS entity_id, DisplayName::text AS label, (Reputation::numeric/1000.0) AS hotness_score, NULL::text AS tags_list, NULL::text AS tag, NULL::int AS rank_within_tag, NULL::int AS global_rank
    FROM Users
    WHERE Reputation < 5
  ) low_reputation
)
-- final select: elaborate projection, sorts, limit for benchmarking
SELECT fc.*,
       -- supplemental correlated metrics: number of distinct commenters on top answers (correlated subquery)
       (
         SELECT count(DISTINCT c.UserId)
         FROM Comments c
         WHERE c.PostId IN (
           SELECT (regexp_split_to_table(coalesce(ta.top_answers_sample,''),'|' ))::text::int
           FROM top_answers ta WHERE ta.QuestionId = fc.entity_id::int
         )
       ) AS distinct_commenters_on_top_answers,
       -- sanity string manipulations for display
       left(fc.label, 120) AS label_snippet,
       coalesce(fc.tags_list, '<no-tags>') AS tags_or_default
FROM final_candidates fc
ORDER BY
  -- order by a combination: prefer questions over other entities, then hotness, then tag/global rank
  CASE WHEN fc.entity_type = 'question' THEN 0 ELSE 1 END,
  fc.hotness_score DESC NULLS LAST,
  coalesce(fc.global_rank, 999999),
  coalesce(fc.rank_within_tag, 999)
LIMIT 100;