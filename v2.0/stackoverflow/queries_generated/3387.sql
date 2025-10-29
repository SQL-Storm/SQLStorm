-- {"query": "3387.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2275} 

WITH
    -- 1. Rank users by reputation (including ties) and keep only the top 200
    top_users AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS rn
        FROM Users u
        WHERE u.Reputation IS NOT NULL
    ),

    -- 2. Aggregate per‑user post statistics (questions vs. answers)
    user_post_stats AS (
        SELECT
            u.Id               AS user_id,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)            AS question_cnt,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)            AS answer_cnt,
            COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score END),0) AS question_score,
            COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END),0) AS answer_score,
            MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END)      AS last_question_date,
            MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate END)      AS last_answer_date
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),

    -- 3. Concatenate badge names per user (NULL when no badge)
    user_badges AS (
        SELECT
            b.UserId                     AS user_id,
            STRING_AGG(b.Name, ', ')      AS badge_list,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_cnt
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- 4. Latest vote activity per post (including up/down counts)
    post_vote_stats AS (
        SELECT
            v.PostId,
            MAX(v.CreationDate)                                                AS last_vote_date,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 2)                           AS up_votes,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 3)                           AS down_votes,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 5)                           AS favorites
        FROM Votes v
        GROUP BY v.PostId
    ),

    -- 5. Explode tags of the most recent question per user
    user_latest_tags AS (
        SELECT
            u.Id                                   AS user_id,
            unnest(string_to_array(
                trim(both '<>' from q.Tags), '><')) AS tag,
            COUNT(*) OVER (PARTITION BY unnest(string_to_array(
                trim(both '<>' from q.Tags), '><'))) AS tag_global_cnt
        FROM top_users u
        JOIN LATERAL (
            SELECT p.Id, p.Tags
            FROM Posts p
            WHERE p.OwnerUserId = u.Id
              AND p.PostTypeId = 1                -- only questions
            ORDER BY p.CreationDate DESC
            LIMIT 1
        ) q ON TRUE
        WHERE q.Tags IS NOT NULL
    ),

    -- 6. Users without any badge (anti‑join)
    users_without_badge AS (
        SELECT u.Id
        FROM top_users u
        LEFT JOIN user_badges ub ON ub.user_id = u.Id
        WHERE ub.user_id IS NULL
    ),

    -- 7. Main payload joining all the pieces together
    main_payload AS (
        SELECT
            tu.Id                                      AS user_id,
            tu.DisplayName,
            tu.Reputation,
            ups.question_cnt,
            ups.answer_cnt,
            ups.question_score,
            ups.answer_score,
            ups.last_question_date,
            ups.last_answer_date,
            COALESCE(ub.badge_list, '(none)')          AS badges,
            COALESCE(ub.gold_cnt,0)                    AS gold_badges,
            COALESCE(ub.silver_cnt,0)                  AS silver_badges,
            COALESCE(ub.bronze_cnt,0)                  AS bronze_badges,
            COALESCE(pvs.up_votes,0)                   AS recent_up_votes,
            COALESCE(pvs.down_votes,0)                 AS recent_down_votes,
            pvs.last_vote_date,
            ut.tag,
            ut.tag_global_cnt,
            CASE
                WHEN ub.user_id IS NULL THEN 1
                ELSE 0
            END                                        AS is_badgeless
        FROM top_users tu
        JOIN user_post_stats ups           ON ups.user_id = tu.Id
        LEFT JOIN user_badges ub          ON ub.user_id = tu.Id
        LEFT JOIN post_vote_stats pvs
               ON pvs.PostId = (
                    SELECT p.Id
                    FROM Posts p
                    WHERE p.OwnerUserId = tu.Id
                      AND p.PostTypeId = 1               -- most recent question
                    ORDER BY p.CreationDate DESC
                    LIMIT 1
               )
        LEFT JOIN user_latest_tags ut    ON ut.user_id = tu.Id
        WHERE tu.rn <= 100
    )

SELECT
    user_id,
    DisplayName,
    Reputation,
    question_cnt,
    answer_cnt,
    (question_score + answer_score)                AS total_score,
    badges,
    gold_badges,
    silver_badges,
    bronze_badges,
    recent_up_votes,
    recent_down_votes,
    COALESCE(last_vote_date,'1970-01-01')          AS last_vote_date,
    tag,
    tag_global_cnt,
    is_badgeless
FROM main_payload
WHERE (question_score + answer_score) > 0
   OR is_badgeless = 1
ORDER BY total_score DESC NULLS LAST, Reputation DESC
LIMIT 50

UNION ALL

SELECT
    NULL                     AS user_id,
    'OVERALL SUMMARY'        AS DisplayName,
    NULL                     AS Reputation,
    SUM(question_cnt)        AS question_cnt,
    SUM(answer_cnt)          AS answer_cnt,
    SUM(question_score+answer_score) AS total_score,
    NULL                     AS badges,
    SUM(gold_badges)         AS gold_badges,
    SUM(silver_badges)       AS silver_badges,
    SUM(bronze_badges)       AS bronze_badges,
    SUM(recent_up_votes)     AS recent_up_votes,
    SUM(recent_down_votes)   AS recent_down_votes,
    NULL                     AS last_vote_date,
    NULL                     AS tag,
    NULL                     AS tag_global_cnt,
    NULL                     AS is_badgeless
FROM main_payload;
