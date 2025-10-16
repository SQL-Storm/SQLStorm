-- {"query": "126.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2764} 
WITH
-- explode tags from question posts
tag_posts AS (
  SELECT
    p.id,
    p.title,
    p.owneruserid,
    p.creationdate,
    p.score,
    COALESCE(p.viewcount,0) AS viewcount,
    -- split tags like '<sql><performance>' into rows: sql, performance
    trim(both '<>' FROM unnest(string_to_array(substring(p.tags,2,length(p.tags)-2), '><'))) AS tag
  FROM posts p
  WHERE p.posttypeid = 1 AND p.tags IS NOT NULL
),

-- aggregate basic metrics per tag
tag_metrics AS (
  SELECT
    tp.tag,
    COUNT(*) AS question_count,
    SUM(tp.viewcount) AS total_views,
    AVG(tp.score) AS avg_question_score,
    MAX(tp.creationdate) AS last_question_at,
    MIN(tp.creationdate) AS first_question_at,
    -- popularity score: mix of views, answers (approx via AnswerCount), and score
    SUM(COALESCE(tp.viewcount,0))::double precision * 0.0001
      + COUNT(*) * 0.5
      + COALESCE(AVG(tp.score),0) * 1.5 AS popularity_estimate
  FROM tag_posts tp
  GROUP BY tp.tag
),

-- compute per-user answer stats (answers only)
user_answer_stats AS (
  SELECT
    u.id AS user_id,
    u.displayname,
    COUNT(a.id) FILTER (WHERE a.posttypeid = 2) AS answer_count,
    SUM(COALESCE(a.score,0))::int AS total_answer_score,
    CASE WHEN COUNT(a.id) > 0 THEN SUM(COALESCE(a.score,0))::double precision / COUNT(a.id) ELSE NULL END AS avg_answer_score,
    MAX(a.creationdate) AS last_answer_at
  FROM users u
  LEFT JOIN posts a ON a.owneruserid = u.id AND a.posttypeid = 2
  GROUP BY u.id, u.displayname
),

-- top answerers per tag (by sum of answer score on answers to questions having that tag)
answers_to_tag AS (
  SELECT
    tp.tag,
    a.owneruserid AS user_id,
    SUM(COALESCE(a.score,0)) AS sum_answer_score,
    COUNT(a.id) AS answers_count,
    MAX(a.creationdate) AS last_answer_at
  FROM tag_posts tp
  JOIN posts q ON q.id = tp.id AND q.posttypeid = 1
  JOIN posts a ON a.parentid = q.id AND a.posttypeid = 2
  GROUP BY tp.tag, a.owneruserid
),

top_answerers_ranked AS (
  SELECT
    at.tag,
    at.user_id,
    COALESCE(u.displayname,'<deleted>') AS displayname,
    at.sum_answer_score,
    at.answers_count,
    RANK() OVER (PARTITION BY at.tag ORDER BY at.sum_answer_score DESC NULLS LAST, at.answers_count DESC) AS score_rank
  FROM answers_to_tag at
  LEFT JOIN users u ON u.id = at.user_id
),

-- for each tag pick top 3 answerers with some additional info (correlated subquery demonstrating per-user historical avg)
top3_answerers AS (
  SELECT
    tar.tag,
    tar.user_id,
    tar.displayname,
    tar.sum_answer_score,
    tar.answers_count,
    tar.score_rank,
    -- correlated subquery: average score across all posts by this user (both Q/A)
    (
      SELECT AVG(COALESCE(p.score,0))::double precision
      FROM posts p
      WHERE p.owneruserid = tar.user_id
    ) AS avg_score_across_all_posts,
    -- flag indicating whether this user has at least one accepted answer (correlated EXISTS)
    EXISTS (
      SELECT 1 FROM posts pa WHERE pa.owneruserid = tar.user_id AND pa.posttypeid = 2 AND pa.id IN (
        SELECT acceptedanswerid FROM posts WHERE acceptedanswerid IS NOT NULL
      )
    ) AS has_accepted_answer
  FROM top_answerers_ranked tar
  WHERE tar.score_rank <= 3
),

-- combine tag metrics with top answerers aggregated into arrays/strings
tag_insights AS (
  SELECT
    tm.tag,
    tm.question_count,
    tm.total_views,
    tm.avg_question_score,
    tm.first_question_at,
    tm.last_question_at,
    tm.popularity_estimate,
    -- top answerers as a concatenated string with NULL handling and string expressions
    COALESCE(
      string_agg(
        CASE
          WHEN t3.displayname IS NULL THEN ('<anon:' || COALESCE(t3.user_id::text,'-') || '>')
          ELSE replace(replace(t3.displayname, E'\n',' '), E'\t',' ')
        END
        || '|' || COALESCE(t3.sum_answer_score::text,'0')
        || '|' || COALESCE(t3.answers_count::text,'0')
        || '|' || COALESCE(ROUND(t3.avg_score_across_all_posts::numeric,2)::text,'NULL')
        || '|' || CASE WHEN t3.has_accepted_answer THEN 'Y' ELSE 'N' END
      ,'; ' ORDER BY t3.score_rank),
      '<no-top-answerers>'
    ) AS top_answerers_summary,
    -- also produce a JSON-like fragment (text) combining some stats
    '{'
      || '"q_count":' || tm.question_count::text || ','
      || '"views":' || tm.total_views::text || ','
      || '"avg_q_score":' || COALESCE(ROUND(tm.avg_question_score::numeric,2)::text,'null')
      || '}' AS mini_json
  FROM tag_metrics tm
  LEFT JOIN top3_answerers t3 ON t3.tag = tm.tag
  GROUP BY tm.tag, tm.question_count, tm.total_views, tm.avg_question_score, tm.first_question_at, tm.last_question_at, tm.popularity_estimate
),

-- also pull tag-like posts from tag wikis (PostTypeId 4/5) to UNION for set operator demonstration
tag_wiki_posts AS (
  SELECT
    p.id,
    p.title AS tagname,
    COALESCE(p.creationdate, '1970-01-01'::timestamp) AS creationdate,
    COALESCE(p.body,'') AS body,
    COALESCE(p.owneruserid, -1) AS owneruserid
  FROM posts p
  WHERE p.posttypeid IN (4,5) -- tag wikis/excerpts
),

-- ex: set operator combining tag_insights with tag_wiki derived rows (synthetic) using UNION ALL to produce a larger test set
tag_insights_union AS (
  SELECT
    ti.tag AS key_name,
    ti.question_count AS metric_a,
    ti.total_views AS metric_b,
    ti.avg_question_score AS metric_c,
    ti.popularity_estimate AS metric_pop,
    ti.top_answerers_summary,
    ti.mini_json,
    ti.first_question_at,
    ti.last_question_at
  FROM tag_insights ti

  UNION ALL

  SELECT
    tw.tagname AS key_name,
    0 AS metric_a,
    0 AS metric_b,
    NULL::double precision AS metric_c,
    -- synthetic popularity estimate using string length and creation age
    (length(coalesce(tw.body,''))::double precision / 100.0)
      + (EXTRACT(EPOCH FROM (now() - tw.creationdate)) / 86400.0 / 365.0) * 0.1 AS metric_pop,
    '<wiki>' AS top_answerers_summary,
    '{ "wiki": true }' AS mini_json,
    tw.creationdate AS first_question_at,
    tw.creationdate AS last_question_at
  FROM tag_wiki_posts tw
)

-- final select with complex predicates, windowing, NULL logic, correlated scalar subquery and ordering
SELECT
  u.key_name AS tag_or_wiki,
  u.metric_a AS question_count,
  u.metric_b AS total_views,
  ROUND(u.metric_c::numeric,2) AS avg_question_score,
  ROUND(u.metric_pop::numeric,4) AS popularity,
  u.top_answerers_summary,
  u.mini_json,
  -- derived recency score using window function relative to tag set
  CASE
    WHEN u.last_question_at IS NULL THEN 0
    ELSE (
      RANK() OVER (ORDER BY u.last_question_at DESC) * 1.0
    )
  END AS recent_rank,
  -- correlated subquery: best badge holder for this tag (by name pattern match against tag text in Badges.Name) --
  (
    SELECT b.name || '::' || COALESCE(us.displayname, 'unknown')
    FROM badges b
    LEFT JOIN users us ON us.id = b.userid
    WHERE (
      -- heuristic: badge name contains the tag (case-insensitive) OR tag appears in mini_json
      lower(b.name) LIKE ('%' || lower(u.key_name) || '%')
      OR u.mini_json ILIKE ('%' || lower(u.key_name) || '%')
    )
    ORDER BY b.date DESC NULLS LAST
    LIMIT 1
  ) AS representative_badge,
  -- demonstrate complicated predicate: pick "hot" tags (popularity plus recent activity) with NULL-safe comparators
  CASE
    WHEN u.metric_pop IS NULL THEN 'cold'
    WHEN u.metric_pop > 10 AND u.question_count > 50 THEN 'very_hot'
    WHEN u.metric_pop > 1 OR (u.question_count > 10 AND u.metric_pop > 0.1) THEN 'hot'
    ELSE 'warm'
  END AS heat_label
FROM tag_insights_union u
WHERE
  -- complex boolean logic, NULL handling, string ops, and existence check for posts mentioning the tag in Title
  (
    (u.metric_pop IS NOT NULL AND u.metric_pop > 0.05)
    OR (COALESCE(u.question_count,0) >= 5)
    OR (u.mini_json ILIKE '%"wiki"%')
  )
  AND (
    -- correlated EXISTS: whether there is at least one question mentioning this tag text in its title (approx)
    EXISTS (
      SELECT 1 FROM posts p2
      WHERE p2.posttypeid = 1
        AND p2.title IS NOT NULL
        AND (
          lower(p2.title) LIKE '%' || lower(regexp_replace(u.key_name, '[^\w]+',' ','g')) || '%'
          OR p2.tags ILIKE ('%<' || u.key_name || '>%')
        )
        LIMIT 1
    )
    OR u.key_name IS NULL -- allow rows that have NULL key_name through, for stress-testing null logic
  )
ORDER BY
  -- combined ordering: first by heat_label (custom ordering via CASE), then by popularity, then recency window
  CASE
    WHEN heat_label = 'very_hot' THEN 1
    WHEN heat_label = 'hot' THEN 2
    WHEN heat_label = 'warm' THEN 3
    ELSE 4
  END,
  u.metric_pop DESC NULLS LAST,
  recent_rank ASC
LIMIT 100;