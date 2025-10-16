-- {"query": "230.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4187} 
WITH
raw_q AS (
  SELECT p.id AS qid,
         p.tags,
         p.creationdate,
         p.score,
         p.viewcount,
         p.answercount,
         p.owneruserid,
         p.acceptedanswerid
  FROM posts p
  WHERE p.posttypeid = 1
    AND p.tags IS NOT NULL
),
raw_a AS (
  SELECT a.id AS aid,
         a.parentid AS qid,
         a.creationdate,
         a.score,
         a.owneruserid
  FROM posts a
  WHERE a.posttypeid = 2
),
q_tags AS (
  SELECT q.qid,
         q.owneruserid AS owneruserid,
         q.score,
         q.viewcount,
         q.creationdate,
         q.answercount,
         q.acceptedanswerid,
         trim(tag) AS tag
  FROM raw_q q
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) AS tag
),
a_tags AS (
  SELECT a.aid,
         a.qid,
         a.owneruserid,
         a.score,
         a.creationdate,
         trim(tag) AS tag,
         CASE WHEN q.acceptedanswerid = a.aid THEN 1 ELSE 0 END AS is_accepted
  FROM raw_a a
  JOIN raw_q q ON q.qid = a.qid
  CROSS JOIN LATERAL unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) AS tag
),
combined AS (
  SELECT tag,
         qid,
         NULL::int AS aid,
         owneruserid,
         score,
         creationdate,
         viewcount,
         answercount,
         0 AS is_answer,
         0 AS is_accepted
  FROM q_tags
  UNION ALL
  SELECT tag,
         qid,
         aid,
         owneruserid,
         score,
         creationdate,
         NULL::int AS viewcount,
         NULL::int AS answercount,
         1 AS is_answer,
         is_accepted
  FROM a_tags
),
tag_agg AS (
  SELECT
    tag,
    count(DISTINCT qid) FILTER (WHERE is_answer = 0) AS question_count,
    count(aid) FILTER (WHERE is_answer = 1) AS answer_count,
    avg(score) FILTER (WHERE is_answer = 0) AS avg_question_score,
    avg(score) FILTER (WHERE is_answer = 1) AS avg_answer_score,
    sum(is_accepted) AS accepted_answers,
    count(*) FILTER (WHERE is_answer = 0 AND answercount = 0) AS unanswered_questions,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY viewcount) FILTER (WHERE viewcount IS NOT NULL) AS median_viewcount,
    min(creationdate) FILTER (WHERE is_answer = 0) AS first_question_date,
    max(creationdate) AS last_activity_date,
    count(DISTINCT owneruserid) FILTER (WHERE owneruserid IS NOT NULL) AS distinct_contributors
  FROM combined
  GROUP BY tag
),
user_contribs AS (
  -- per tag, per user contributions (questions count, answers count, score sum, accepted count)
  SELECT
    tag,
    owneruserid AS user_id,
    sum(CASE WHEN is_answer = 0 THEN 1 ELSE 0 END) AS q_posts,
    sum(CASE WHEN is_answer = 1 THEN 1 ELSE 0 END) AS a_posts,
    sum(COALESCE(score,0)) AS total_score,
    sum(is_accepted) AS accepted_count
  FROM combined
  WHERE owneruserid IS NOT NULL
  GROUP BY tag, owneruserid
),
top_users AS (
  SELECT
    uc.tag,
    uc.user_id,
    uc.q_posts,
    uc.a_posts,
    uc.total_score,
    uc.accepted_count,
    -- heuristic composite score: answers weighted more, accepted answers bonus, plus reputation-like score from post scores
    (uc.a_posts * 5) + (uc.q_posts * 2) + (uc.accepted_count * 10) + (uc.total_score::float / GREATEST(NULLIF(uc.q_posts + uc.a_posts,0),1)) AS composite_score,
    row_number() OVER (PARTITION BY uc.tag ORDER BY (uc.a_posts * 5) + (uc.q_posts * 2) + (uc.accepted_count * 10) + (uc.total_score::float / GREATEST(NULLIF(uc.q_posts + uc.a_posts,0),1)) DESC, uc.user_id) AS rn
  FROM user_contribs uc
),
top3_users AS (
  SELECT t.tag,
         t.user_id,
         t.composite_score,
         u.displayname,
         u.reputation
  FROM top_users t
  LEFT JOIN users u ON u.id = t.user_id
  WHERE t.rn <= 3
),
top_answers_per_tag AS (
  SELECT tag, aid, qid, owneruserid, score,
         row_number() OVER (PARTITION BY tag ORDER BY score DESC NULLS LAST, creationdate) AS rank_in_tag
  FROM a_tags
),
top3_answers AS (
  SELECT tag, aid, qid, owneruserid, score
  FROM top_answers_per_tag
  WHERE rank_in_tag <= 3
),
last_edit_per_tag AS (
  SELECT qt.tag,
         ph.posthistorytypeid,
         pht.name AS last_history_name,
         ph.creationdate AS last_history_date
  FROM (
    SELECT tag, max(ph.creationdate) AS max_cd
    FROM q_tags qt
    JOIN posthistory ph ON ph.postid = qt.qid
    GROUP BY tag
  ) latest
  JOIN q_tags qt ON qt.tag = latest.tag
  JOIN posthistory ph ON ph.postid = qt.qid AND ph.creationdate = latest.max_cd
  LEFT JOIN posthistorytypes pht ON pht.id = ph.posthistorytypeid
),
tag_quality AS (
  SELECT
    t.tag,
    t.question_count,
    t.answer_count,
    t.unanswered_questions,
    t.median_viewcount,
    t.accepted_answers,
    t.distinct_contributors,
    t.first_question_date,
    t.last_activity_date,
    COALESCE(t.accepted_answers::float / NULLIF(GREATEST(t.answer_count,1),0), 0) AS accepted_ratio,
    -- churn: questions per active contributor
    COALESCE(t.question_count::float / NULLIF(t.distinct_contributors,0), t.question_count) AS q_per_contributor
  FROM tag_agg t
),
hot_tags AS (
  SELECT tag
  FROM tag_quality
  WHERE (question_count >= 500 OR median_viewcount >= 20000 OR accepted_ratio > 0.6)
),
cold_tags AS (
  SELECT tag
  FROM tag_quality
  WHERE (question_count BETWEEN 1 AND 50 AND unanswered_questions > GREATEST(5, question_count/5))
),
selected_tags AS (
  -- union of hot and cold but mark them
  SELECT ht.tag, 'hot' AS category FROM hot_tags ht
  UNION
  SELECT ct.tag, 'cold' AS category FROM cold_tags ct
),
final AS (
  SELECT
    tq.tag,
    st.category,
    tq.question_count,
    tq.answer_count,
    tq.unanswered_questions,
    tq.median_viewcount,
    tq.accepted_answers,
    round(tq.accepted_ratio::numeric, 4) AS accepted_ratio,
    tq.distinct_contributors,
    to_char(tq.first_question_date, 'YYYY-MM-DD') AS first_q,
    to_char(tq.last_activity_date, 'YYYY-MM-DD') AS last_act,
    to_char(coalesce(let.last_history_date, tq.last_activity_date), 'YYYY-MM-DD"T"HH24:MI:SS') AS last_edit,
    -- assemble top users as comma separated list
    (SELECT string_agg(coalesce(u.displayname, 'user:'||tu.user_id||' (id='||tu.user_id||')') || ':' || round(tu.composite_score::numeric,2), ', ' ORDER BY tu.composite_score DESC)
     FROM top_users tu
     LEFT JOIN users u ON u.id = tu.user_id
     WHERE tu.tag = tq.tag AND tu.rn <= 3) AS top_users_brief,
    -- list of top answers ids for quick inspection
    (SELECT string_agg('A' || ta.aid || '(@Q' || ta.qid || '):' || coalesce(ta.score::text,'0'), ', ' ORDER BY ta.score DESC)
     FROM top3_answers ta WHERE ta.tag = tq.tag) AS top_3_answers,
    -- sample title keywords from questions in the tag (correlated subquery with regex and aggregation)
    (SELECT string_agg(distinct word, ', ' ORDER BY count DESC LIMIT 8)
     FROM (
       SELECT lower(regexp_replace(regexp_matches(coalesce(p.title,''), '([A-Za-z][A-Za-z0-9_+#+-]{1,})','g')::text, '[^A-Za-z0-9_+#+-]','', 'g')) AS word,
              count(*) AS count
       FROM q_tags qt2
       JOIN posts p ON p.id = qt2.qid
       WHERE qt2.tag = tq.tag AND p.title IS NOT NULL
       GROUP BY 1
       ORDER BY count DESC
     ) kw) AS top_title_keywords
  FROM tag_quality tq
  JOIN selected_tags st ON st.tag = tq.tag
  LEFT JOIN last_edit_per_tag let ON let.tag = tq.tag
)
SELECT *
FROM final
ORDER BY category DESC, question_count DESC, median_viewcount DESC
LIMIT 200;