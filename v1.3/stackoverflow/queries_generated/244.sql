-- {"query": "244.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3632} 
WITH
-- explode question tags into rows
question_tags AS (
  SELECT p.id AS question_id,
         p.owneruserid,
         p.creationdate AS question_creation,
         NULLIF(p.tags, '') AS tags_raw,
         TRIM(t) AS tag
  FROM posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) AS t
  ) s
  WHERE p.posttypeid = 1 AND p.tags IS NOT NULL
),
-- all answers with parent linkage and score
answers AS (
  SELECT p.id AS answer_id,
         p.parentid AS question_id,
         p.owneruserid AS answer_owner,
         p.creationdate AS answer_creation,
         p.score AS answer_score
  FROM posts p
  WHERE p.posttypeid = 2
),
-- combine question-tag pairs with answers (may be NULL for questions with no answers)
qt_with_answers AS (
  SELECT qt.tag,
         qt.question_id,
         qt.owneruserid AS question_owner,
         qt.question_creation,
         a.answer_id,
         a.answer_owner,
         a.answer_creation,
         a.answer_score,
         -- is this answer the accepted answer for the question?
         CASE WHEN (SELECT acceptedanswerid FROM posts WHERE id = qt.question_id) = a.answer_id THEN 1 ELSE 0 END AS is_accepted,
         -- acceptance delay in seconds when this answer is accepted; NULL otherwise
         CASE WHEN (SELECT acceptedanswerid FROM posts WHERE id = qt.question_id) = a.answer_id
              THEN EXTRACT(EPOCH FROM (a.answer_creation - qt.question_creation))
              ELSE NULL END AS accept_delay_secs
  FROM question_tags qt
  LEFT JOIN answers a ON a.question_id = qt.question_id
),
-- lateral-derived latest comment per user per tag (correlated subquery demonstrating lateral/correlated behavior)
latest_user_comment AS (
  SELECT DISTINCT ON (u.id, t.tag)
         u.id AS user_id,
         t.tag,
         c.text AS latest_comment_text,
         c.creationdate AS latest_comment_date
  FROM users u
  CROSS JOIN (SELECT DISTINCT tag FROM question_tags) t
  LEFT JOIN LATERAL (
    SELECT c.text, c.creationdate
    FROM comments c
    JOIN posts p ON p.id = c.postid
    WHERE c.userid = u.id
      AND p.tags IS NOT NULL
      AND p.tags LIKE ('%<' || t.tag || '>%')  -- coarse filter to find comments on posts having the tag
    ORDER BY c.creationdate DESC
    LIMIT 1
  ) c ON TRUE
  WHERE u.id IS NOT NULL
),
-- event stream: unify ask/answer events for per-user per-tag aggregation
events AS (
  SELECT tag,
         question_owner AS user_id,
         'ask' AS role,
         1 AS cnt,
         0 AS is_accepted,
         NULL::double precision AS accept_delay_secs,
         0 AS post_score,
         question_creation AS evt_date,
         question_id AS post_id
  FROM question_tags

  UNION ALL

  SELECT tag,
         answer_owner AS user_id,
         'answer' AS role,
         CASE WHEN answer_id IS NULL THEN 0 ELSE 1 END AS cnt,
         COALESCE(is_accepted, 0) AS is_accepted,
         accept_delay_secs,
         COALESCE(answer_score,0) AS post_score,
         answer_creation AS evt_date,
         answer_id AS post_id
  FROM qt_with_answers
),
-- aggregate metrics per tag per user
per_tag_user AS (
  SELECT e.tag,
         e.user_id,
         COALESCE(u.displayname, ('user_' || e.user_id::text)) AS displayname,
         SUM(CASE WHEN e.role = 'ask' THEN e.cnt ELSE 0 END) AS questions_asked,
         SUM(CASE WHEN e.role = 'answer' THEN e.cnt ELSE 0 END) AS answers_posted,
         SUM(e.is_accepted) AS answers_accepted,
         AVG(NULLIF(e.post_score,0)) FILTER (WHERE e.role = 'answer' AND e.post_score IS NOT NULL) AS avg_answer_score,
         COUNT(DISTINCT e.post_id) AS distinct_posts,
         MIN(e.evt_date) AS first_activity,
         MAX(e.evt_date) AS last_activity,
         AVG(e.accept_delay_secs) FILTER (WHERE e.is_accepted = 1) AS avg_accept_delay_secs,
         SUM(e.post_score) AS total_score
  FROM events e
  LEFT JOIN users u ON u.id = e.user_id
  GROUP BY e.tag, e.user_id, u.displayname
),
-- tag-level totals for normalization
tag_totals AS (
  SELECT tag,
         SUM(questions_asked) AS total_questions,
         SUM(answers_posted) AS total_answers,
         COUNT(*) FILTER (WHERE questions_asked > 0 OR answers_posted > 0) AS active_users
  FROM per_tag_user
  GROUP BY tag
),
-- build composite ranking score with null-safe arithmetic and penalize long average accept delays
ranked AS (
  SELECT ptu.*,
         tt.total_questions,
         tt.total_answers,
         tt.active_users,
         -- composite metric: weighted combination of accepted rate, avg answer score, activity density, normalized by avg accept delay (with null logic)
         COALESCE(
           (
             (CASE WHEN ptu.answers_posted > 0 THEN ptu.answers_accepted::double precision / ptu.answers_posted ELSE 0 END) * 3.0
             + COALESCE(ptu.avg_answer_score, 0) * 1.5
             + LEAST(1, GREATEST(0, (ptu.questions_asked + ptu.answers_posted) / NULLIF(tt.active_users,0))) * 2.0
             + (COALESCE(ptu.total_score,0) / NULLIF(GREATEST(ptu.distinct_posts,1),1)) * 0.5
           ) / NULLIF(1 + COALESCE(ptu.avg_accept_delay_secs, 0) / 86400.0, 1)
         , 0) AS composite_score,
         -- rank within tag
         ROW_NUMBER() OVER (PARTITION BY ptu.tag ORDER BY
            COALESCE(
              (
                (CASE WHEN ptu.answers_posted > 0 THEN ptu.answers_accepted::double precision / ptu.answers_posted ELSE 0 END) * 3.0
                + COALESCE(ptu.avg_answer_score, 0) * 1.5
                + LEAST(1, GREATEST(0, (ptu.questions_asked + ptu.answers_posted) / NULLIF(tt.active_users,0))) * 2.0
                + (COALESCE(ptu.total_score,0) / NULLIF(GREATEST(ptu.distinct_posts,1),1)) * 0.5
              ) / NULLIF(1 + COALESCE(ptu.avg_accept_delay_secs, 0) / 86400.0, 1)
            , 0) DESC,
            ptu.total_score DESC,
            ptu.last_activity DESC
         ) AS rn,
         -- dense rank based on composite
         DENSE_RANK() OVER (PARTITION BY ptu.tag ORDER BY COALESCE(ptu.total_score,0) DESC) AS score_rank
  FROM per_tag_user ptu
  JOIN tag_totals tt ON tt.tag = ptu.tag
),
-- top contributors per tag (top 3)
top_per_tag AS (
  SELECT r.*
  FROM ranked r
  WHERE r.rn <= 3
),
-- attach badge counts and recent activity snippets using outer joins and correlated subqueries demonstrating NULL logic
user_enrichment AS (
  SELECT tpt.*,
         COALESCE(b.badge_count, 0) AS badge_count,
         COALESCE(u.reputation, 0) AS reputation,
         COALESCE(luc.latest_comment_text, '(no recent comment)') AS latest_comment,
         -- recent edit activity on posts with this tag (correlated subquery)
         (SELECT p.title FROM posts p WHERE p.owneruserid = tpt.user_id AND p.posttypeid = 1 AND p.tags LIKE ('%<' || tpt.tag || '>%') ORDER BY p.lasteditdate DESC NULLS LAST LIMIT 1) AS latest_question_title_with_tag
  FROM top_per_tag tpt
  LEFT JOIN (
    SELECT userId, COUNT(*) AS badge_count
    FROM badges
    GROUP BY userId
  ) b ON b.userId = tpt.user_id
  LEFT JOIN users u ON u.id = tpt.user_id
  LEFT JOIN latest_user_comment luc ON luc.user_id = tpt.user_id AND luc.tag = tpt.tag
)
-- final result: combine top contributors with tag aggregates and also include tags that have many questions but no top contributors (set operator example)
SELECT ue.tag,
       ue.user_id,
       ue.displayname,
       ue.reputation,
       ue.badge_count,
       ue.questions_asked,
       ue.answers_posted,
       ue.answers_accepted,
       COALESCE(ROUND(ue.avg_answer_score::numeric,2), 0) AS avg_answer_score,
       COALESCE(ROUND(ue.avg_accept_delay_secs::numeric,2), NULL) AS avg_accept_delay_secs,
       ue.distinct_posts,
       ue.total_score,
       COALESCE(ue.latest_comment, '(none)') AS latest_comment,
       COALESCE(ue.latest_question_title_with_tag, '(no recent question)') AS latest_question_title_with_tag,
       ue.composite_score,
       ue.rn,
       ue.score_rank
FROM user_enrichment ue

UNION

-- include tags with many questions but no users in top_per_tag (demonstrates set operator and NULL logic)
SELECT tt.tag,
       NULL::int AS user_id,
       '(community)'::text AS displayname,
       NULL::int AS reputation,
       0 AS badge_count,
       NULL::int AS questions_asked,
       NULL::int AS answers_posted,
       NULL::int AS answers_accepted,
       NULL::numeric AS avg_answer_score,
       NULL::numeric AS avg_accept_delay_secs,
       NULL::int AS distinct_posts,
       NULL::int AS total_score,
       '(n/a)'::text AS latest_comment,
       '(n/a)'::text AS latest_question_title_with_tag,
       0.0 AS composite_score,
       NULL::int AS rn,
       NULL::int AS score_rank
FROM tag_totals tt
WHERE tt.total_questions > 200  -- heavy tags
  AND tt.tag NOT IN (SELECT tag FROM user_enrichment)

ORDER BY tag, composite_score DESC NULLS LAST, reputation DESC NULLS LAST;