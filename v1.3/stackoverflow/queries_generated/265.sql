-- {"query": "265.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3576} 
WITH
questions AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate::date AS qdate,
    p.Score,
    p.ViewCount,
    p.AcceptedAnswerId,
    COALESCE(p.Tags,'') AS raw_tags,
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::varchar[] ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') END AS tag_array
  FROM Posts p
  WHERE p.PostTypeId = 1
),
question_tags AS (
  SELECT q.*, t.tag
  FROM questions q
  CROSS JOIN LATERAL unnest(q.tag_array) AS t(tag)
),
tag_aggregates AS (
  SELECT
    qt.tag,
    COUNT(*) AS question_count,
    AVG(qt.Score) AS avg_q_score,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qt.Score) AS median_q_score,
    SUM(COALESCE(qt.ViewCount,0)) AS total_views,
    SUM(CASE WHEN qt.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_count
  FROM question_tags qt
  GROUP BY qt.tag
),
answers AS (
  SELECT a.Id, a.ParentId, a.OwnerUserId, a.CreationDate::date AS a_date, a.Score
  FROM Posts a
  WHERE a.PostTypeId = 2
),
tag_answer_stats AS (
  SELECT
    qt.tag,
    COUNT(a.Id) AS answer_count,
    AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS avg_answer_score,
    SUM(CASE WHEN a.Id = qt.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_answer_hits
  FROM question_tags qt
  LEFT JOIN answers a ON a.ParentId = qt.Id
  GROUP BY qt.tag
),
top_contributors AS (
  SELECT
    qt.tag,
    a.OwnerUserId,
    COUNT(*) AS answers_by_user,
    RANK() OVER (PARTITION BY qt.tag ORDER BY COUNT(*) DESC) AS rk
  FROM question_tags qt
  JOIN Posts a ON a.PostTypeId = 2 AND a.ParentId = qt.Id AND a.OwnerUserId IS NOT NULL
  GROUP BY qt.tag, a.OwnerUserId
),
top_contrib_first AS (
  SELECT tag, OwnerUserId AS top_user, answers_by_user
  FROM top_contributors
  WHERE rk = 1
),
daily_activity AS (
  SELECT
    qdate,
    COUNT(*) AS questions,
    SUM(COALESCE(ViewCount,0)) AS views,
    AVG(COALESCE(Score,0)) AS avg_score
  FROM questions
  GROUP BY qdate
  ORDER BY qdate
),
daily_moving AS (
  SELECT
    d.*,
    AVG(questions) OVER (ORDER BY qdate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS moving_avg_weekly_questions,
    SUM(views) OVER (ORDER BY qdate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS monthly_views_sum
  FROM daily_activity d
),
ranked_tags AS (
  SELECT
    ta.tag,
    ta.question_count,
    ta.total_views,
    ta.avg_q_score,
    ta.median_q_score,
    tas.answer_count,
    tas.avg_answer_score,
    tcf.top_user,
    ROW_NUMBER() OVER (ORDER BY ta.question_count DESC NULLS LAST, ta.total_views DESC) AS tag_rank
  FROM tag_aggregates ta
  LEFT JOIN tag_answer_stats tas USING (tag)
  LEFT JOIN top_contrib_first tcf USING (tag)
)
SELECT
  rt.tag_rank,
  rt.tag,
  rt.question_count,
  rt.total_views,
  COALESCE(rt.avg_q_score,0)::numeric(10,3) AS avg_q_score,
  COALESCE(rt.median_q_score,0)::numeric(10,3) AS median_q_score,
  COALESCE(rt.answer_count,0) AS answer_count,
  COALESCE(rt.avg_answer_score,0)::numeric(10,3) AS avg_answer_score,
  rt.top_user,
  u.DisplayName AS top_user_name,
  -- correlated subquery: count of distinct answerer locations for this tag (NULLs coalesced)
  (
    SELECT COUNT(DISTINCT COALESCE(us.Location,'<unknown>'))
    FROM Posts a
    JOIN Users us ON a.OwnerUserId = us.Id
    WHERE a.PostTypeId = 2
      AND a.ParentId IN (SELECT q.Id FROM questions q WHERE q.tag_array @> ARRAY[rt.tag])
  ) AS distinct_answerer_locations,
  -- sample concatenated recent titles (top 5) for the tag
  (
    SELECT string_agg(substring(s.Title,1,50),' || ')
    FROM (
      SELECT Title
      FROM Posts q2
      WHERE q2.PostTypeId = 1
        AND q2.Tags LIKE ('%<'||rt.tag||'>%')
      ORDER BY q2.CreationDate DESC
      LIMIT 5
    ) s
  ) AS sample_titles,
  -- correlated subquery using EXISTS and complex boolean/NULL logic: whether there exists a high-rep gold-badged user answering frequently on this tag
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Posts a2
      WHERE a2.PostTypeId = 2
        AND a2.ParentId IN (SELECT q.Id FROM questions q WHERE q.tag_array @> ARRAY[rt.tag])
        AND a2.OwnerUserId IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM Badges b2
          WHERE b2.UserId = a2.OwnerUserId AND b2.Class = 1
        )
      GROUP BY a2.OwnerUserId
      HAVING COUNT(*) > 10
    ) THEN TRUE
    ELSE FALSE
  END AS has_prolific_gold_answerer,
  -- tag profile heuristic using NULL logic and numeric comparisons
  CASE
    WHEN rt.median_q_score IS NULL OR rt.question_count < 10 THEN 'low-data'
    WHEN rt.total_views > 100000 AND COALESCE(rt.avg_q_score,0) > 1 THEN 'hot'
    WHEN COALESCE(rt.avg_q_score,0) < 0 THEN 'controversial'
    ELSE 'stable'
  END AS tag_profile
FROM ranked_tags rt
LEFT JOIN Users u ON u.Id = rt.top_user
WHERE rt.question_count > 0
ORDER BY rt.tag_rank
LIMIT 100;