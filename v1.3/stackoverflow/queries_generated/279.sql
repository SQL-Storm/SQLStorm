-- {"query": "279.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4635} 
WITH
recent_posts AS (
  SELECT *
  FROM Posts
  WHERE CreationDate >= NOW() - INTERVAL '365 days'
),
exploded_tags AS (
  SELECT p.Id AS PostId, trim(t.tg) AS Tag
  FROM recent_posts p
  CROSS JOIN LATERAL unnest(
    string_to_array(
      substring(p.Tags, 2, length(p.Tags)-2),
      '><'
    )
  ) AS t(tg)
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
tag_stats AS (
  SELECT
    et.Tag,
    COUNT(*) AS questions_recent,
    COUNT(a.Id) AS recent_answers_to_tag,
    AVG(q.Score) FILTER (WHERE q.PostTypeId=1) AS avg_question_score,
    SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS questions_with_accept,
    AVG(EXTRACT(EPOCH FROM (aa.CreationDate - q.CreationDate))/3600.0) FILTER (WHERE aa.CreationDate IS NOT NULL) AS avg_hours_to_accept,
    MAX(q.ViewCount) AS max_views,
    COUNT(DISTINCT NULLIF(q.OwnerUserId,-1)) AS distinct_askers
  FROM exploded_tags et
  LEFT JOIN Posts q ON q.Id = et.PostId
  LEFT JOIN Posts a ON a.ParentId = q.Id
  LEFT JOIN Posts aa ON aa.Id = q.AcceptedAnswerId
  GROUP BY et.Tag
),
user_contribs AS (
  SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, ('user_' || u.Id::text)) AS DisplayName,
    COALESCE(SUM(CASE WHEN p.PostTypeId=1 THEN 1 ELSE 0 END),0) AS q_count,
    COALESCE(SUM(CASE WHEN p.PostTypeId=2 THEN 1 ELSE 0 END),0) AS a_count,
    COALESCE(AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL),0) AS avg_post_score,
    MAX(p.CreationDate) AS last_post_date
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
tag_top_users AS (
  SELECT
    et.Tag,
    uc.UserId,
    uc.DisplayName,
    SUM(CASE WHEN p.PostTypeId=2 THEN 1 ELSE 0 END) AS answers_for_tag,
    SUM(CASE WHEN p.PostTypeId=1 THEN 1 ELSE 0 END) AS questions_for_tag,
    COALESCE(AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL), 0) AS avg_score_for_tag
  FROM exploded_tags et
  JOIN Posts p ON (CASE WHEN p.PostTypeId=1 THEN p.Id ELSE p.ParentId END) = et.PostId
    AND p.PostTypeId IN (1,2)
  JOIN user_contribs uc ON uc.UserId = p.OwnerUserId
  WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
  GROUP BY et.Tag, uc.UserId, uc.DisplayName
),
tag_leaders AS (
  SELECT
    tt.Tag,
    tt.UserId,
    tt.DisplayName,
    tt.answers_for_tag,
    tt.avg_score_for_tag,
    ROW_NUMBER() OVER (PARTITION BY tt.Tag ORDER BY tt.answers_for_tag DESC, tt.avg_score_for_tag DESC, tt.UserId) AS rn
  FROM tag_top_users tt
),
top_three_per_tag AS (
  SELECT Tag,
    string_agg(format('%s (uid=%s,ans=%s,avg=%.2f)', DisplayName, UserId, answers_for_tag, avg_score_for_tag), '; ' ORDER BY answers_for_tag DESC, avg_score_for_tag DESC)
      FILTER (WHERE rn <= 3) AS top_3_users
  FROM tag_leaders
  WHERE rn <= 3
  GROUP BY Tag
),
tag_ranking AS (
  SELECT
    ts.*,
    ttp.top_3_users,
    DENSE_RANK() OVER (ORDER BY ts.questions_recent DESC NULLS LAST, ts.recent_answers_to_tag DESC NULLS LAST) AS popularity_rank,
    ROW_NUMBER() OVER (ORDER BY COALESCE(ts.avg_question_score,0) DESC, COALESCE(ts.avg_hours_to_accept,1e9) ASC) AS quality_rank
  FROM tag_stats ts
  LEFT JOIN top_three_per_tag ttp ON ttp.Tag = ts.Tag
),
alt_calcs AS (
  SELECT Tag, questions_recent, recent_answers_to_tag, avg_question_score, 'A'::text AS source
  FROM tag_stats
  WHERE questions_recent > 5
  UNION ALL
  SELECT Tag, questions_recent, recent_answers_to_tag, NULL::double precision AS avg_question_score, 'B'::text AS source
  FROM tag_stats
  WHERE questions_recent <= 5
),
alt_filtered AS (
  SELECT * FROM alt_calcs
  EXCEPT
  SELECT Tag, questions_recent, recent_answers_to_tag, avg_question_score, source FROM alt_calcs WHERE source='B' AND questions_recent < 2
),
median_scores AS (
  SELECT t.Tag,
    (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY p2.Score)
     FROM Posts p2
     WHERE p2.PostTypeId = 2
       AND EXISTS (
         SELECT 1 FROM exploded_tags et2 WHERE et2.PostId = p2.ParentId AND et2.Tag = t.Tag
       )
    ) AS median_answer_score
  FROM (SELECT DISTINCT Tag FROM tag_stats) t
)
SELECT
  tr.Tag,
  tr.questions_recent,
  tr.recent_answers_to_tag,
  COALESCE(tr.avg_question_score,0)::numeric(10,2) AS avg_question_score,
  COALESCE(tr.avg_hours_to_accept, -1)::numeric(10,2) AS avg_hours_to_accept,
  tr.max_views,
  tr.distinct_askers,
  tr.popularity_rank,
  tr.quality_rank,
  COALESCE(m.median_answer_score,0)::numeric(10,2) AS median_answer_score,
  COALESCE(tr.top_3_users, '<no top users>') AS top_3_users,
  CASE
    WHEN tr.questions_recent > 50 THEN 'hot'
    WHEN tr.questions_recent BETWEEN 20 AND 50 THEN 'active'
    WHEN tr.questions_recent BETWEEN 6 AND 19 THEN 'moderate'
    ELSE 'niche'
  END AS tag_activity_label,
  -- a diagnostic boolean mixing NULL logic and regex-like string check
  (COALESCE(tr.top_3_users, '') <> '')::boolean AS has_top_users,
  -- include a sample of alt_filtered existence via correlated EXISTS
  EXISTS(SELECT 1 FROM alt_filtered af WHERE af.Tag = tr.Tag AND af.questions_recent IS NOT NULL) AS in_alt_filtered
FROM tag_ranking tr
LEFT JOIN median_scores m ON m.Tag = tr.Tag
WHERE (tr.questions_recent IS NOT NULL AND tr.questions_recent > 0)
  AND (tr.avg_question_score IS NULL OR tr.avg_question_score >= -5)
  AND NOT (tr.Tag IS NULL OR length(tr.Tag) < 1)
ORDER BY tr.popularity_rank, tr.quality_rank, tr.Tag
LIMIT 250;