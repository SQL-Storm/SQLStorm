-- {"query": "555.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3182}
WITH recent_users AS (
    SELECT
        u.id AS user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        COALESCE(NULLIF(TRIM(u.websiteurl), ''), 'unknown') AS website_normalized,
        date_trunc('month', u.creationdate) AS signup_month,
        row_number() OVER (PARTITION BY COALESCE(u.location, 'unknown') ORDER BY u.reputation DESC, u.id) AS rn_loc_rep
    FROM users u
    WHERE u.creationdate >= (
        SELECT max(p.creationdate) - INTERVAL '5 years' FROM posts p
    )
),
user_badge_stats AS (
    SELECT
        b.userid,
        count(*) AS badge_count,
        sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_count,
        sum(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_count,
        sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_count,
        min(b.date) AS first_badge_date,
        max(b.date) AS last_badge_date
    FROM badges b
    GROUP BY b.userid
),
questions AS (
    SELECT
        p.id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.lastactivitydate,
        p.answercount,
        p.commentcount,
        date_trunc('month', p.creationdate) AS q_month
    FROM posts p
    WHERE p.posttypeid = 1
),
answers AS (
    SELECT
        a.id,
        a.parentid AS question_id,
        a.owneruserid,
        a.creationdate,
        a.score,
        a.commentcount,
        row_number() OVER (PARTITION BY a.parentid ORDER BY a.score DESC NULLS LAST, a.creationdate) AS rn_best_by_score,
        rank() OVER (PARTITION BY a.parentid ORDER BY a.creationdate) AS rk_earliest,
        date_trunc('month', a.creationdate) AS a_month
    FROM posts a
    WHERE a.posttypeid = 2
),
question_activity AS (
    SELECT
        q.id AS question_id,
        q.owneruserid AS asker_id,
        q.creationdate AS question_date,
        q.score AS question_score,
        q.viewcount AS question_views,
        q.title,
        q.tags,
        q.acceptedanswerid,
        q.closeddate,
        q.lastactivitydate,
        q.answercount,
        q.commentcount,
        min(a.creationdate) AS first_answer_date,
        max(a.creationdate) AS last_answer_date,
        count(a.id) AS total_answers,
        sum(CASE WHEN a.score > 0 THEN 1 ELSE 0 END) AS positive_answers,
        sum(a.commentcount) AS total_answer_comments
    FROM questions q
    LEFT JOIN answers a ON a.question_id = q.id
    GROUP BY q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tags, q.acceptedanswerid, q.closeddate, q.lastactivitydate, q.answercount, q.commentcount
),
tag_expansion AS (
    SELECT
        q.id AS question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags) - 2, 0)), '><')) AS tag
    FROM questions q
    WHERE q.tags IS NOT NULL
),
tag_meta AS (
    SELECT
        te.tag,
        count(*) AS tagged_questions,
        sum(CASE WHEN qa.question_score >= 5 THEN 1 ELSE 0 END) AS hot_questions,
        avg(CAST(qa.question_views AS numeric)) AS avg_views
    FROM tag_expansion te
    JOIN question_activity qa ON qa.question_id = te.question_id
    GROUP BY te.tag
),
dup_links AS (
    SELECT
        pl.postid AS dup_post_id,
        pl.relatedpostid AS original_post_id,
        pl.creationdate AS link_date
    FROM postlinks pl
    WHERE pl.linktypeid = 3
),
close_events AS (
    SELECT
        ph.postid,
        ph.creationdate AS closed_at,
        -- cast empty string to int is not portable; attempt safe conversion:
        CASE WHEN ph.comment = '' THEN NULL
             WHEN ph.comment ~ '^[0-9]+$' THEN CAST(ph.comment AS integer)
             ELSE NULL
        END AS close_reason_id
    FROM posthistory ph
    WHERE ph.posthistorytypeid = 10
),
reopen_events AS (
    SELECT
        ph.postid,
        ph.creationdate AS reopened_at
    FROM posthistory ph
    WHERE ph.posthistorytypeid = 11
),
question_status AS (
    SELECT
        qa.question_id,
        qa.asker_id,
        qa.question_date,
        qa.question_score,
        qa.question_views,
        qa.title,
        qa.tags,
        qa.acceptedanswerid,
        qa.closeddate,
        qa.lastactivitydate,
        qa.answercount,
        qa.commentcount,
        qa.first_answer_date,
        qa.last_answer_date,
        qa.total_answers,
        qa.positive_answers,
        qa.total_answer_comments,
        de.original_post_id,
        ce.close_reason_id,
        ce.closed_at,
        re.reopened_at,
        CASE
            WHEN ce.postid IS NOT NULL AND re.reopened_at IS NULL THEN 'closed'
            WHEN ce.postid IS NOT NULL AND re.reopened_at IS NOT NULL AND re.reopened_at > ce.closed_at THEN 'reopened'
            ELSE 'open'
        END AS lifecycle_status
    FROM question_activity qa
    LEFT JOIN dup_links de ON de.dup_post_id = qa.question_id
    LEFT JOIN close_events ce ON ce.postid = qa.question_id
    LEFT JOIN reopen_events re ON re.postid = qa.question_id
),
votes_agg AS (
    SELECT
        v.postid,
        sum(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
        sum(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
        sum(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS favorites,
        sum(CASE WHEN v.votetypeid IN (8,9) THEN COALESCE(v.bountyamount,0) ELSE 0 END) AS bounty_total,
        min(CASE WHEN v.votetypeid = 2 THEN v.creationdate ELSE NULL END) AS first_upvote_at
    FROM votes v
    GROUP BY v.postid
),
comment_activity AS (
    SELECT
        c.postid,
        count(*) AS comments_count,
        max(c.creationdate) AS last_comment_at,
        sum(CASE WHEN c.score > 0 THEN 1 ELSE 0 END) AS positive_comments
    FROM comments c
    GROUP BY c.postid
),
answerer_quality AS (
    SELECT
        a.owneruserid AS user_id,
        count(*) AS answers_posted,
        avg(CAST(a.score AS numeric)) AS avg_answer_score,
        sum(CASE WHEN a.rn_best_by_score = 1 THEN 1 ELSE 0 END) AS times_top_scored,
        sum(CASE WHEN a.rk_earliest = 1 THEN 1 ELSE 0 END) AS times_first_answerer
    FROM answers a
    WHERE a.owneruserid IS NOT NULL
    GROUP BY a.owneruserid
),
accepted_stats AS (
    SELECT
        q.owneruserid AS asker_id,
        count(*) FILTER (WHERE q.acceptedanswerid IS NOT NULL) AS questions_with_accepted,
        count(*) AS total_questions,
        avg(EXTRACT(EPOCH FROM (a.creationdate - q.creationdate)) / 3600.0) FILTER (WHERE q.acceptedanswerid IS NOT NULL) AS avg_hours_to_accepted
    FROM questions q
    LEFT JOIN posts a ON a.id = q.acceptedanswerid
    GROUP BY q.owneruserid
),
post_owner AS (
    SELECT
        p.id AS post_id,
        COALESCE(p.owneruserid, -1) AS owner_id,
        p.posttypeid
    FROM posts p
),
owner_rollup AS (
    SELECT
        po.owner_id,
        count(*) FILTER (WHERE po.posttypeid = 1) AS questions_authored,
        count(*) FILTER (WHERE po.posttypeid = 2) AS answers_authored
    FROM post_owner po
    GROUP BY po.owner_id
),
monthly_user_activity AS (
    SELECT
        u.id AS user_id,
        date_trunc('month', p.creationdate) AS month,
        count(*) FILTER (WHERE p.posttypeid = 1) AS q_count,
        count(*) FILTER (WHERE p.posttypeid = 2) AS a_count,
        count(*) FILTER (WHERE p.posttypeid NOT IN (1,2) OR p.posttypeid IS NULL) AS other_posts
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id
    GROUP BY u.id, date_trunc('month', p.creationdate)
),
best_answer_per_question AS (
    SELECT
        a.question_id,
        a.id AS answer_id,
        a.owneruserid AS answerer_id,
        a.score,
        row_number() OVER (PARTITION BY a.question_id ORDER BY a.score DESC NULLS LAST, a.creationdate) AS rn
    FROM answers a
),
best_answerers AS (
    SELECT
        b.answerer_id AS user_id,
        count(*) AS best_answers
    FROM best_answer_per_question b
    WHERE b.rn = 1
    GROUP BY b.answerer_id
),
string_metrics AS (
    SELECT
        q.id AS question_id,
        length(COALESCE(q.title, '')) AS title_len,
        length(regexp_replace(COALESCE(q.title, ''), '[aeiouAEIOU]', '', 'g')) AS consonant_title_len,
        length(COALESCE(q.tags, '')) AS tags_len,
        position('java' IN lower(COALESCE(q.title,''))) AS pos_java_in_title,
        CASE WHEN q.tags ILIKE '%<python>%' THEN 1 ELSE 0 END AS has_python_tag
    FROM questions q
),
final AS (
    SELECT
        qs.question_id,
        qs.asker_id,
        u.displayname AS asker_name,
        COALESCE(u.location, 'unknown') AS asker_location,
        u.reputation AS asker_reputation,
        ub.badge_count,
        ub.gold_count,
        ub.silver_count,
        ub.bronze_count,
        o.questions_authored,
        o.answers_authored,
        aq.answers_posted,
        aq.avg_answer_score,
        aq.times_top_scored,
        aq.times_first_answerer,
        ac.questions_with_accepted,
        ac.total_questions AS asker_total_questions,
        ac.avg_hours_to_accepted,
        (va.upvotes - va.downvotes) AS net_votes,
        va.favorites,
        va.bounty_total,
        COALESCE(va.first_upvote_at, qs.question_date) AS first_upvote_at,
        COALESCE(ca.comments_count, 0) AS comments_count,
        COALESCE(ca.positive_comments, 0) AS positive_comments,
        ca.last_comment_at,
        qs.question_date,
        qs.first_answer_date,
        qs.last_answer_date,
        qs.total_answers,
        qs.positive_answers,
        qs.total_answer_comments,
        qs.question_score,
        qs.question_views,
        qs.title,
        qs.tags,
        qs.lifecycle_status,
        qs.original_post_id,
        qs.close_reason_id,
        tm.tagged_questions,
        tm.hot_questions,
        tm.avg_views AS tag_avg_views,
        sm.title_len,
        sm.consonant_title_len,
        sm.tags_len,
        sm.pos_java_in_title,
        sm.has_python_tag,
        date_part('day', COALESCE(qs.first_answer_date, CAST('2024-10-01 12:34:56' AS timestamp)) - qs.question_date) AS days_to_first_answer,
        CASE
            WHEN qs.acceptedanswerid IS NOT NULL THEN 'accepted'
            WHEN qs.total_answers > 0 THEN 'answered'
            ELSE 'unanswered'
        END AS answer_status,
        sum(CASE WHEN ml.month IS NOT NULL THEN 1 ELSE 0 END) OVER (
            PARTITION BY u.id
            ORDER BY COALESCE(ml.month, date_trunc('month', qs.question_date))
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS active_months_cume,
        dense_rank() OVER (ORDER BY u.reputation DESC NULLS LAST, qs.question_views DESC) AS dr_global_rep_view
    FROM question_status qs
    LEFT JOIN users u ON u.id = qs.asker_id
    LEFT JOIN user_badge_stats ub ON ub.userid = qs.asker_id
    LEFT JOIN owner_rollup o ON o.owner_id = qs.asker_id
    LEFT JOIN votes_agg va ON va.postid = qs.question_id
    LEFT JOIN comment_activity ca ON ca.postid = qs.question_id
    LEFT JOIN tag_expansion te ON te.question_id = qs.question_id
    LEFT JOIN tag_meta tm ON tm.tag = te.tag
    LEFT JOIN string_metrics sm ON sm.question_id = qs.question_id
    LEFT JOIN accepted_stats ac ON ac.asker_id = qs.asker_id
    LEFT JOIN answerer_quality aq ON aq.user_id = qs.asker_id
    LEFT JOIN monthly_user_activity ml ON ml.user_id = qs.asker_id AND date_trunc('month', qs.question_date) = ml.month
),
ranked AS (
    SELECT
        f.*,
        row_number() OVER (
            PARTITION BY COALESCE(f.asker_location, 'unknown')
            ORDER BY (f.net_votes + COALESCE(f.favorites,0) + f.question_views/10.0) DESC NULLS LAST, f.question_date DESC
        ) AS rn_loc
    FROM final f
    WHERE
        (f.has_python_tag = 1 OR f.pos_java_in_title > 0 OR f.tagged_questions >= 100)
        AND COALESCE(f.lifecycle_status, 'open') <> 'closed'
        AND COALESCE(f.asker_reputation, 0) >= 1
        AND (f.title_len BETWEEN 10 AND 200 OR f.title_len IS NULL)
)
SELECT
    r.question_id,
    r.asker_id,
    r.asker_name,
    r.asker_location,
    r.asker_reputation,
    r.badge_count,
    r.gold_count,
    r.silver_count,
    r.bronze_count,
    r.questions_authored,
    r.answers_authored,
    r.question_date,
    r.first_answer_date,
    r.days_to_first_answer,
    r.answer_status,
    r.total_answers,
    r.question_score,
    r.net_votes,
    r.favorites,
    r.bounty_total,
    r.tagged_questions,
    r.hot_questions,
    r.tag_avg_views,
    r.title_len,
    r.consonant_title_len,
    r.has_python_tag,
    r.pos_java_in_title,
    r.dr_global_rep_view,
    r.rn_loc,
    COALESCE(r.title, '[no title]') AS title,
    COALESCE(r.tags, '') AS tags
FROM ranked r
WHERE r.rn_loc <= 50
ORDER BY r.dr_global_rep_view, r.asker_location, r.rn_loc;