-- {"query": "268.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3386} 
WITH exploded_tags AS (
  SELECT
    p.Id AS qid,
    trim(tag) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags) - 2), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1
),
tag_agg AS (
  SELECT
    et.tag,
    count(*) AS question_count,
    avg(p.Score) AS avg_score,
    sum(p.ViewCount) AS total_views,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score
  FROM exploded_tags et
  JOIN Posts p ON p.Id = et.qid
  GROUP BY et.tag
  HAVING count(*) > 10
),
question_features AS (
  SELECT
    p.Id AS question_id,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    et.tag,
    /* correlated subquery: actual number of answers */
    (SELECT count(*) FROM Posts a WHERE a.ParentId = p.Id) AS actual_answer_count,
    /* top 3 answerers for the question (by reputation) as a comma-separated list */
    (SELECT string_agg(s.DisplayName, ', ')
     FROM (
       SELECT u.DisplayName, u.Reputation
       FROM Posts pa
       JOIN Users u ON pa.OwnerUserId = u.Id
       WHERE pa.ParentId = p.Id AND pa.OwnerUserId IS NOT NULL
       GROUP BY u.DisplayName, u.Reputation
       ORDER BY u.Reputation DESC NULLS LAST
       LIMIT 3
     ) s
    ) AS top_answerers,
    /* latest comment text (correlated subquery using LIMIT) */
    (SELECT c.Text FROM Comments c WHERE c.PostId = p.Id ORDER BY c.CreationDate DESC LIMIT 1) AS latest_comment,
    /* accepted answer snapshot */
    pa.Score AS accepted_answer_score,
    pa.OwnerUserId AS accepted_answer_owner,
    /* window functions across tag partition */
    row_number() OVER (PARTITION BY et.tag ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.CreationDate ASC) AS rank_in_tag,
    dense_rank() OVER (PARTITION BY et.tag ORDER BY p.Score DESC NULLS LAST) AS dense_rank_score,
    ntile(10) OVER (PARTITION BY et.tag ORDER BY p.ViewCount DESC NULLS LAST) AS decile_views,
    /* string expressions and null-aware concatenation */
    trim(coalesce(p.Title, '')) || ' [' || coalesce(et.tag, 'untagged') || ']' AS title_with_tag
  FROM Posts p
  JOIN exploded_tags et ON et.qid = p.Id
  LEFT JOIN Posts pa ON pa.Id = p.AcceptedAnswerId
  WHERE p.PostTypeId = 1
),
combined AS (
  -- high-volume tags slice
  SELECT
    qf.*,
    ta.question_count,
    ta.avg_score,
    ta.total_views,
    ta.median_score,
    -- a somewhat elaborate scoring expression using logs, null logic, and ratios
    (
      COALESCE(qf.Score, 0) * ln(1 + GREATEST(COALESCE(qf.ViewCount, 0), 0) + 1)
      * (1 + COALESCE((qf.accepted_answer_score)::numeric / NULLIF(qf.actual_answer_count, 0), 0))
      * (1 + (ta.avg_score / NULLIF(ABS(ta.median_score) + 1, 0)))
      / (1 + GREATEST(qf.rank_in_tag::numeric - 1, 0))
    ) + (
      /* small boost for recent activity: decays by age in days */
      EXP(-EXTRACT(EPOCH FROM (now() - qf.CreationDate)) / 86400.0 / 30.0) * 10
    ) AS hotness_score
  FROM question_features qf
  JOIN tag_agg ta ON ta.tag = qf.tag
  WHERE qf.rank_in_tag <= 100
  
  UNION ALL
  
  -- low-volume tags (different scoring to stress set operator and alternative plan)
  SELECT
    qf.*,
    ta.question_count,
    ta.avg_score,
    ta.total_views,
    ta.median_score,
    (
      (COALESCE(qf.Score, 0) + COALESCE(ta.avg_score, 0) / NULLIF(LEAST(ta.question_count, 100)::numeric, 0))
      * (1 + sqrt(GREATEST(COALESCE(qf.ViewCount, 0), 1))) 
      * CASE WHEN qf.actual_answer_count IS NULL OR qf.actual_answer_count = 0 THEN 1.25 ELSE 1.0 END
      + (CASE WHEN qf.top_answerers IS NULL THEN 0 ELSE length(qf.top_answerers) END) * 0.1
    ) / (1 + qf.rank_in_tag::numeric)
    AS hotness_score
  FROM question_features qf
  JOIN tag_agg ta ON ta.tag = qf.tag
  WHERE ta.question_count BETWEEN 2 AND 10
),
-- remove any rows where owner is unknown via EXCEPT (demonstrates set operator)
filtered AS (
  SELECT
    question_id, Title, Tags, OwnerUserId, Score, ViewCount, CreationDate, tag,
    actual_answer_count, top_answerers, latest_comment, accepted_answer_score, accepted_answer_owner,
    rank_in_tag, dense_rank_score, decile_views, title_with_tag,
    question_count, avg_score, total_views, median_score, hotness_score
  FROM combined

  EXCEPT

  SELECT
    question_id, Title, Tags, OwnerUserId, Score, ViewCount, CreationDate, tag,
    actual_answer_count, top_answerers, latest_comment, accepted_answer_score, accepted_answer_owner,
    rank_in_tag, dense_rank_score, decile_views, title_with_tag,
    question_count, avg_score, total_views, median_score, hotness_score
  FROM combined
  WHERE OwnerUserId IS NULL
),
-- produce final ordering with additional windowed aggregates for benchmarking
final_ranked AS (
  SELECT
    f.*,
    rank() OVER (ORDER BY hotness_score DESC NULLS LAST) AS global_rank,
    avg(hotness_score) OVER (PARTITION BY tag) AS avg_hotness_by_tag,
    min(hotness_score) OVER (PARTITION BY tag) AS min_hotness_by_tag,
    max(hotness_score) OVER (PARTITION BY tag) AS max_hotness_by_tag,
    count(*) OVER (PARTITION BY tag) AS rows_per_tag,
    /* complex boolean predicate combining null logic and pattern matching */
    (CASE
      WHEN (Title ILIKE '%error%' OR coalesce(latest_comment, '') ILIKE '%error%') AND COALESCE(accepted_answer_score, 0) > 0 THEN true
      WHEN OwnerUserId IS NULL OR COALESCE(Score, 0) < -5 THEN false
      ELSE (decile_views <= 3 AND actual_answer_count >= 1)
    END) AS candidate_flag
  FROM filtered f
)
SELECT
  question_id,
  title_with_tag,
  tag,
  OwnerUserId,
  Score,
  ViewCount,
  actual_answer_count,
  top_answerers,
  coalesce(substring(Tags from 1 for 200), '') AS tags_snippet,
  coalesce(latest_comment, '[no comments]') AS latest_comment_preview,
  accepted_answer_score,
  hotness_score,
  global_rank,
  avg_hotness_by_tag,
  min_hotness_by_tag,
  max_hotness_by_tag,
  rows_per_tag,
  candidate_flag
FROM final_ranked
WHERE candidate_flag = true OR global_rank <= 200
ORDER BY hotness_score DESC NULLS LAST, avg_hotness_by_tag DESC
LIMIT 500;