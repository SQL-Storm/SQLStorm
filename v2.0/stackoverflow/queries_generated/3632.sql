-- {"query": "3632.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2931} 

WITH
    badge_counts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)                AS gold_badges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)                AS silver_badges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)                AS bronze_badges,
            COUNT(*)                                                    AS total_badges
        FROM Badges b
        GROUP BY b.UserId
    ),
    post_stats AS (
        SELECT
            p.OwnerUserId                                            AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)                 AS question_count,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)                 AS answer_count,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)             AS avg_question_score,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)             AS avg_answer_score,
            MAX(p.CreationDate)                                      AS last_post_date,
            SUM(
                CASE
                    WHEN p.Tags IS NOT NULL
                    THEN (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', ''))) / 2 + 1
                    ELSE 0
                END
            )                                                        AS tag_appearances
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    recent_activity AS (
        SELECT
            ua.UserId,
            ua.activity_dt,
            ua.activity_type,
            ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY ua.activity_dt DESC) AS rn
        FROM (
            SELECT
                p.OwnerUserId               AS UserId,
                p.CreationDate              AS activity_dt,
                CASE WHEN p.PostTypeId = 1 THEN 'question' ELSE 'answer' END AS activity_type
            FROM Posts p
            WHERE p.OwnerUserId IS NOT NULL

            UNION ALL

            SELECT
                c.UserId                    AS UserId,
                c.CreationDate              AS activity_dt,
                'comment'                   AS activity_type
            FROM Comments c
            WHERE c.UserId IS NOT NULL
        ) ua
    ),
    tag_stats AS (
        SELECT
            t.TagName,
            t.Count                                          AS tag_global_count,
            COALESCE(SUM(p.AnswerCount),0)                   AS total_answers_on_tag,
            COUNT(DISTINCT p.Id)                             AS distinct_questions_on_tag
        FROM Tags t
        LEFT JOIN Posts p
            ON p.PostTypeId = 1
           AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
        GROUP BY t.TagName, t.Count
    ),
    high_score_posts AS (
        SELECT
            p.OwnerUserId,
            COUNT(*) AS high_score_post_cnt
        FROM Posts p
        WHERE p.Score > (
                SELECT COALESCE(AVG(score),0)
                FROM Posts
                WHERE PostTypeId = 1
              )
          AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    active_users AS (
        SELECT OwnerUserId AS user_id FROM Posts   WHERE CreationDate > CURRENT_DATE - INTERVAL '30 days'
        INTERSECT
        SELECT UserId      AS user_id FROM Comments WHERE CreationDate > CURRENT_DATE - INTERVAL '30 days'
    )
SELECT
    u.Id                                         AS user_id,
    u.DisplayName,
    u.Reputation,
    COALESCE(bc.gold_badges,0)                   AS gold_badges,
    COALESCE(bc.silver_badges,0)                 AS silver_badges,
    COALESCE(bc.bronze_badges,0)                 AS bronze_badges,
    COALESCE(ps.question_count,0)                AS questions_posted,
    COALESCE(ps.answer_count,0)                  AS answers_posted,
    ROUND(COALESCE(ps.avg_question_score,0)::numeric,2) AS avg_q_score,
    ROUND(COALESCE(ps.avg_answer_score,0)::numeric,2)   AS avg_a_score,
    COALESCE(ps.tag_appearances,0)               AS total_tag_mentions,
    COALESCE(hsp.high_score_post_cnt,0)          AS high_score_posts,
    ra.last_activity_date,
    CASE
        WHEN u.Location ILIKE '%usa%' THEN 'North America'
        WHEN u.Location ILIKE '%uk%'  THEN 'Europe'
        ELSE 'Other'
    END                                          AS region,
    CASE
        WHEN u.EmailHash IS NULL THEN 'NoEmail'
        ELSE 'HasEmail'
    END                                          AS email_status,
    CASE WHEN au.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_active_last_30d
FROM Users u
LEFT JOIN badge_counts      bc  ON bc.UserId = u.Id
LEFT JOIN post_stats        ps  ON ps.UserId = u.Id
LEFT JOIN high_score_posts  hsp ON hsp.OwnerUserId = u.Id
LEFT JOIN (
        SELECT UserId, MAX(activity_dt) AS last_activity_date
        FROM recent_activity
        WHERE rn = 1
        GROUP BY UserId
    ) ra ON ra.UserId = u.Id
LEFT JOIN active_users au ON au.user_id = u.Id
WHERE
    (u.Reputation > 1000 OR COALESCE(bc.total_badges,0) > 5)
    AND NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.ClosedDate IS NOT NULL
    )
    AND (u.CreationDate < CURRENT_DATE - INTERVAL '5 years'
         OR u.LastAccessDate > CURRENT_DATE - INTERVAL '30 days')
ORDER BY
    u.Reputation DESC NULLS LAST,
    gold_badges DESC,
    (COALESCE(ps.question_count,0) + COALESCE(ps.answer_count,0)) DESC
LIMIT 100
OFFSET 0;
