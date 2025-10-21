-- {"query": "39004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3169} 

WITH
    recent_posts AS (
        SELECT p.id, p.posttypeid, p.creationdate, p.tags, p.owneruserid
        FROM Posts p
        WHERE p.creationdate >= now() - interval '1 year'
    ),
    tag_questions AS (
        SELECT
            p.id AS qid,
            unnest(string_to_array(substring(p.tags, 2, length(p.tags) - 2), '><')) AS tag
        FROM recent_posts p
        WHERE p.posttypeid = 1
    ),
    answer_times AS (
        SELECT
            a.parentid AS qid,
            min(a.creationdate - q.creationdate) AS first_answer_interval
        FROM Posts a
        JOIN Posts q ON a.parentid = q.id
        WHERE a.posttypeid = 2
          AND q.creationdate >= now() - interval '1 year'
        GROUP BY a.parentid
    ),
    tag_stats AS (
        SELECT
            tq.tag,
            count(*)                        AS question_count,
            avg(q.score)                    AS avg_question_score,
            avg(at.first_answer_interval)   AS avg_response_interval
        FROM tag_questions tq
        JOIN Posts q ON tq.qid = q.id
        LEFT JOIN answer_times at ON tq.qid = at.qid
        GROUP BY tq.tag
    ),
    user_metrics AS (
        SELECT
            u.id           AS user_id,
            u.displayname,
            count(*) FILTER (WHERE p.posttypeid = 1) AS questions_asked,
            count(*) FILTER (WHERE p.posttypeid = 2) AS answers_given,
            avg(p.score) FILTER (WHERE p.posttypeid = 2)   AS avg_answer_score
        FROM Users u
        JOIN Posts p ON p.owneruserid = u.id
        WHERE p.creationdate >= now() - interval '1 year'
        GROUP BY u.id, u.displayname
    ),
    top_users AS (
        SELECT
            um.*,
            rank() OVER (ORDER BY um.answers_given DESC NULLS LAST) AS answer_rank
        FROM user_metrics um
    ),
    monthly_rep AS (
        SELECT
            date_trunc('month', v.creationdate) AS month,
            v.userid,
            sum(
                CASE vt.name
                    WHEN 'UpMod'               THEN 10
                    WHEN 'AcceptedByOriginator' THEN 15
                    WHEN 'DownMod'             THEN -2
                    ELSE 0
                END
            ) AS rep_delta
        FROM Votes v
        JOIN VoteTypes vt ON v.votetypeid = vt.id
        WHERE v.creationdate >= now() - interval '1 year'
        GROUP BY 1, v.userid
    ),
    user_rep AS (
        SELECT
            mr.userid,
            jsonb_agg(
                jsonb_build_object(
                    'month', to_char(mr.month, 'YYYY-MM'),
                    'delta', mr.rep_delta
                ) ORDER BY mr.month
            ) AS monthly_representation
        FROM monthly_rep mr
        GROUP BY mr.userid
    )
SELECT
    jsonb_build_object(
        'top_tags',
        (
            SELECT jsonb_agg(
                       jsonb_build_object(
                           'tag', ts.tag,
                           'questions', ts.question_count,
                           'avg_score', round(ts.avg_question_score::numeric,2),
                           'avg_resp_hours', round(extract(epoch FROM ts.avg_response_interval)/3600,2)
                       )
                   ORDER BY ts.question_count DESC
                   LIMIT 5)
            FROM tag_stats ts
        ),
        'top_users',
        (
            SELECT jsonb_agg(
                       jsonb_build_object(
                           'rank', tu.answer_rank,
                           'user', tu.displayname,
                           'answers', tu.answers_given,
                           'avg_ans_score', round(tu.avg_answer_score::numeric,2),
                           'monthly_rep', ur.monthly_representation
                       )
                   ORDER BY tu.answer_rank
                   LIMIT 5)
            FROM top_users tu
            LEFT JOIN user_rep ur ON tu.user_id = ur.userid
        )
    ) AS performance_report;
