-- {"query": "309.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20307} 
WITH
user_agg AS (
  SELECT
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    COALESCE(u.views,0) AS user_views,
    COUNT(DISTINCT p.id) FILTER (WHERE p.posttypeid = 1) AS q_count,
    COUNT(DISTINCT p.id) FILTER (WHERE p.posttypeid = 2) AS a_count,
    SUM(COALESCE(p.score,0)) FILTER (WHERE p.posttypeid IN (1,2)) AS total_post_score,
    AVG(COALESCE(p.score,0)) FILTER (WHERE p.posttypeid IN (1,2)) AS avg_post_score,
    COUNT(DISTINCT b.id) AS badges_count,
    MAX(b.date) AS last_badge_date
  FROM Users u
  LEFT JOIN Posts p ON p.owneruserid = u.id
  LEFT JOIN Badges b ON b.userid = u.id
  GROUP BY u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.views
),
user_metrics AS (
  SELECT ua.*,
         ROW_NUMBER() OVER (ORDER BY ua.reputation DESC NULLS LAST) AS rep_rank,
         RANK() OVER (ORDER BY (COALESCE(ua.q_count,0) + COALESCE(ua.a_count,0)) DESC NULLS LAST) AS activity_rank
  FROM user_agg ua
),
question_tags AS (
  SELECT
    q.id AS question_id,
    q.title,
    q.creationdate,
    q.score AS question_score,
    tag.tag
  FROM Posts q
  CROSS JOIN LATERAL regexp_split_to_table(regexp_replace(COALESCE(q.tags, ''), '^<|>$', '', 'g'), '><') AS tag(tag)
  WHERE q.posttypeid = 1 AND q.tags IS NOT NULL
),
answers_stats AS (
  SELECT
    q.id AS question_id,
    q.creationdate AS question_creation,
    COUNT(a.id) FILTER (WHERE a.id IS NOT NULL) AS answers_count,
    MIN(a.creationdate) AS first_answer_date,
    AVG(a.score) AS avg_answer_score,
    MAX(a.score) AS max_answer_score,
    SUM(CASE WHEN a.id = q.acceptedanswerid THEN 1 ELSE 0 END) AS accepted_flag,
    (SELECT a2.owneruserid FROM Posts a2 WHERE a2.parentid = q.id ORDER BY a2.creationdate ASC NULLS LAST LIMIT 1) AS fastest_answer_user,
    EXTRACT(EPOCH FROM (MIN(a.creationdate) - q.creationdate)) AS secs_to_first_answer
  FROM Posts q
  LEFT JOIN Posts a ON a.parentid = q.id AND a.posttypeid = 2
  WHERE q.posttypeid = 1
  GROUP BY q.id, q.creationdate, q.acceptedanswerid
),
post_engagement AS (
  SELECT
    p.id AS post_id,
    p.posttypeid,
    p.parentid,
    p.creationdate,
    COALESCE(v.votes_total,0) AS votes_total,
    COALESCE(v.upvotes,0) AS upvotes,
    COALESCE(v.downvotes,0) AS downvotes,
    COALESCE(c.c_count,0) AS comments_count,
    COALESCE(pl.duplicates,0) AS duplicates_linked
  FROM Posts p
  LEFT JOIN (
    SELECT postid,
           COUNT(*) AS votes_total,
           SUM(CASE WHEN votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
           SUM(CASE WHEN votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Votes
    GROUP BY postid
  ) v ON v.postid = p.id
  LEFT JOIN (
    SELECT postid, COUNT(*) AS c_count FROM Comments GROUP BY postid
  ) c ON c.postid = p.id
  LEFT JOIN (
    SELECT postid, SUM(CASE WHEN linktypeid = 3 THEN 1 ELSE 0 END) AS duplicates FROM PostLinks GROUP BY postid
  ) pl ON pl.postid = p.id
),
top_answers AS (
  SELECT id, score, viewcount, 'answer'::text AS kind FROM Posts WHERE posttypeid = 2 ORDER BY score DESC LIMIT 100
),
top_questions AS (
  SELECT id, score, viewcount, 'question'::text AS kind FROM Posts WHERE posttypeid = 1 ORDER BY score DESC LIMIT 100
),
high_scoring AS (
  SELECT * FROM top_answers
  UNION
  SELECT * FROM top_questions
),
most_viewed AS (
  SELECT id, score, viewcount FROM Posts WHERE viewcount IS NOT NULL ORDER BY viewcount DESC LIMIT 100
),
hot_posts AS (
  SELECT id, score, viewcount FROM high_scoring
  INTERSECT
  SELECT id, score, viewcount FROM most_viewed
),
tag_counts AS (
  SELECT
    qt.tag,
    COUNT(DISTINCT qt.question_id) AS questions,
    COUNT(DISTINCT CASE WHEN as_.answers_count > 0 THEN qt.question_id END) AS questions_with_answers,
    AVG(as_.answers_count::numeric) AS avg_answers_per_question,
    SUM(COALESCE(e.votes_total,0)) FILTER (WHERE p.posttypeid = 1) AS votes_on_questions,
    SUM(COALESCE(e.votes_total,0)) FILTER (WHERE p.posttypeid = 2) AS votes_on_answers,
    AVG(as_.secs_to_first_answer) AS avg_secs_to_first_answer,
    SUM(as_.accepted_flag) AS accepted_sum,
    SUM(as_.answers_count) AS total_answers
  FROM question_tags qt
  LEFT JOIN Posts p ON p.id = qt.question_id
  LEFT JOIN answers_stats as_ ON as_.question_id = qt.question_id
  LEFT JOIN post_engagement e ON e.post_id = qt.question_id
  GROUP BY qt.tag
  HAVING COUNT(DISTINCT qt.question_id) > 5
),
tag_leaderboard AS (
  SELECT
    tag,
    questions,
    questions_with_answers,
    avg_answers_per_question,
    votes_on_questions,
    votes_on_answers,
    avg_secs_to_first_answer,
    CASE WHEN total_answers = 0 THEN NULL ELSE accepted_sum::numeric / total_answers END AS acceptance_ratio,
    RANK() OVER (ORDER BY questions DESC) AS tag_popularity_rank
  FROM tag_counts
),
per_user_recent AS (
  SELECT
    p.owneruserid AS user_id,
    p.id AS post_id,
    p.posttypeid,
    p.creationdate,
    p.score,
    AVG(p.score) OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS rolling_avg_score_5,
    ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate DESC) AS rn_desc
  FROM Posts p
  WHERE p.owneruserid IS NOT NULL
),
suspicious_activity AS (
  SELECT
    ph.userid,
    COUNT(*) FILTER (WHERE ph.posthistorytypeid IN (12,50)) AS deletions_or_bumps,
    MAX(ph.creationdate) AS last_history_date,
    BOOL_OR(ph.posthistorytypeid = 12) AS has_deletion
  FROM PostHistory ph
  GROUP BY ph.userid
  HAVING COUNT(*) FILTER (WHERE ph.posthistorytypeid IN (12,50)) > 3
),
high_rep AS (
  SELECT id FROM Users WHERE reputation >= 10000
),
active_scholars AS (
  SELECT user_id AS id FROM per_user_recent WHERE rn_desc <= 20 GROUP BY user_id HAVING COUNT(*) > 5
),
reliable_high_rep AS (
  SELECT id FROM high_rep
  INTERSECT
  SELECT id FROM active_scholars
  EXCEPT
  SELECT userid FROM suspicious_activity WHERE userid IS NOT NULL
),
final_candidates AS (
  SELECT
    u.id AS user_id,
    u.displayname,
    um.rep_rank,
    um.activity_rank,
    COALESCE(um.q_count,0) AS q_count,
    COALESCE(um.a_count,0) AS a_count,
    COALESCE(um.total_post_score,0) AS total_post_score,
    COALESCE(s.deletions_or_bumps,0) AS deletions_or_bumps,
    COALESCE(s.has_deletion, FALSE) AS has_deletion,
    COUNT(DISTINCT b.id) FILTER (WHERE b.class = 1) AS gold_badges,
    COUNT(DISTINCT b.id) FILTER (WHERE b.class = 2) AS silver_badges,
    COUNT(DISTINCT b.id) FILTER (WHERE b.class = 3) AS bronze_badges,
    (
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (a.creationdate - q.creationdate)))
      FROM Posts a JOIN Posts q ON a.parentid = q.id
      WHERE a.owneruserid = u.id AND q.posttypeid = 1 AND a.creationdate IS NOT NULL AND q.creationdate IS NOT NULL
    ) AS median_secs_between_question_and_answer,
    (
      SELECT string_agg(sub.tag, ',' ORDER BY sub.cnt DESC)
      FROM (
        SELECT qt.tag, COUNT(*) AS cnt
        FROM question_tags qt
        JOIN Posts p2 ON p2.id = qt.question_id
        WHERE p2.owneruserid = u.id
        GROUP BY qt.tag
      ) sub
    ) AS top_tags_csv,
    AVG((LENGTH(COALESCE(p.body, '')) - COALESCE(p.score,0)*5)::numeric) AS avg_body_complexity
  FROM Users u
  LEFT JOIN user_metrics um ON um.id = u.id
  LEFT JOIN suspicious_activity s ON s.userid = u.id
  LEFT JOIN Badges b ON b.userid = u.id
  LEFT JOIN Posts p ON p.owneruserid = u.id
  GROUP BY u.id, u.displayname, um.rep_rank, um.activity_rank, um.q_count, um.a_count, um.total_post_score, s.deletions_or_bumps, s.has_deletion
  HAVING COALESCE(um.q_count,0) + COALESCE(um.a_count,0) > 0
)
SELECT
  fc.user_id,
  fc.displayname,
  fc.rep_rank,
  fc.activity_rank,
  fc.q_count,
  fc.a_count,
  fc.total_post_score,
  fc.gold_badges,
  fc.silver_badges,
  fc.bronze_badges,
  tl.tag_popularity_rank,
  tl.questions,
  COALESCE(tl.avg_answers_per_question,0) AS avg_answers_per_question,
  COALESCE(tl.acceptance_ratio,0) AS acceptance_ratio,
  to_char(COALESCE(fc.median_secs_between_question_and_answer,0) * interval '1 second', 'HH24:MI:SS') AS median_response_time,
  CASE WHEN fc.deletions_or_bumps > 0 THEN 'suspicious' WHEN fc.rep_rank <= 100 THEN 'elite' ELSE 'regular' END AS user_tier,
  (
    SELECT string_agg('post:'||hp.id||'('||hp.viewcount||'v,'||hp.score||'s)', ';' ORDER BY hp.viewcount DESC)
    FROM hot_posts hp JOIN Posts p ON p.id = hp.id
    WHERE p.owneruserid = fc.user_id
  ) AS hot_posts_summary,
  LEFT(COALESCE(fc.top_tags_csv, ''), 200) AS top_tags_snippet,
  (
    SELECT tag FROM tag_leaderboard t WHERE t.tag = split_part(fc.top_tags_csv, ',',1) LIMIT 1
  ) AS best_tag_if_present,
  fc.avg_body_complexity
FROM final_candidates fc
LEFT JOIN tag_leaderboard tl ON tl.tag = split_part(fc.top_tags_csv, ',',1)
WHERE fc.user_id IN (SELECT id FROM reliable_high_rep)
ORDER BY fc.rep_rank ASC NULLS LAST, fc.activity_rank ASC NULLS LAST
LIMIT 200;