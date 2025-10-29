-- {"query": "3618.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1867}
WITH 
gold_badge_users AS (
    SELECT 
        u.Id                               AS user_id,
        COALESCE(u.DisplayName, 'Anonymous') AS display_name,
        u.Reputation,
        COUNT(b.Id)                        AS gold_badge_cnt,
        MAX(b.Date)                        AS last_gold_badge_date
    FROM Users u
    LEFT JOIN Badges b 
           ON b.UserId = u.Id 
          AND b.Class = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 0
),
high_rep_users AS (
    SELECT 
        u.Id                               AS user_id,
        COALESCE(u.DisplayName, 'Anonymous') AS display_name,
        u.Reputation,
        0                                 AS gold_badge_cnt,
        CAST(NULL AS TIMESTAMP)           AS last_gold_badge_date
    FROM Users u
    WHERE u.Reputation >= 100000
),
recent_activity AS (
    SELECT 
        uid,
        MAX(activity_dt) AS last_activity_dt
    FROM (
        SELECT 
            p.OwnerUserId AS uid,
            p.CreationDate AS activity_dt
        FROM Posts p
        WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days')
          AND p.OwnerUserId IS NOT NULL

        UNION ALL

        SELECT 
            c.UserId AS uid,
            c.CreationDate AS activity_dt
        FROM Comments c
        WHERE c.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days')
          AND c.UserId IS NOT NULL
    ) a
    GROUP BY uid
),
user_tag_stats AS (
    SELECT 
        p.OwnerUserId                     AS user_id,
        COUNT(*)                          AS question_cnt,
        AVG(p.Score)                      AS avg_question_score,
        STRING_AGG(DISTINCT tag, ', ')    AS tag_list
    FROM (
        SELECT p.*,
               UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.OwnerUserId IS NOT NULL
    ) p
    GROUP BY p.OwnerUserId
),
user_answer_counts AS (
    SELECT 
        u.Id                              AS user_id,
        (SELECT COUNT(*) 
         FROM Posts a 
         WHERE a.PostTypeId = 2
           AND a.OwnerUserId = u.Id) AS answer_cnt
    FROM Users u
),
duplicate_links AS (
    SELECT 
        p.Id                              AS question_id,
        dl.Id                             AS duplicate_of_id,
        pl.CreationDate                   AS duplicate_link_date
    FROM Posts p
    LEFT JOIN PostLinks pl 
           ON pl.PostId = p.Id 
          AND pl.LinkTypeId = 3
    LEFT JOIN Posts dl 
           ON dl.Id = pl.RelatedPostId
    WHERE p.PostTypeId = 1
),
combined_users AS (
    SELECT * FROM gold_badge_users
    UNION
    SELECT * FROM high_rep_users
),
final_result AS (
    SELECT 
        cu.user_id,
        cu.display_name,
        cu.Reputation,
        cu.gold_badge_cnt,
        COALESCE(uts.question_cnt, 0)          AS question_cnt,
        COALESCE(uts.avg_question_score, 0)    AS avg_question_score,
        COALESCE(uac.answer_cnt, 0)            AS answer_cnt,
        COALESCE(ra.last_activity_dt, 
                 CAST('1970-01-01' AS TIMESTAMP))       AS last_activity_dt,
        COALESCE(uts.tag_list, '')             AS tag_list,
        COALESCE(dl.duplicate_of_id, -1)       AS duplicate_of_question_id,
        ROW_NUMBER() OVER (
            ORDER BY 
                cu.gold_badge_cnt DESC,
                cu.Reputation   DESC,
                uts.avg_question_score DESC
        )                                      AS reputation_rank,
        CASE 
            WHEN cu.gold_badge_cnt = 0 THEN 
                ('No gold(' || cu.Reputation || ')')
            ELSE 
                ('Gold:' || cu.gold_badge_cnt ||
                       ' Rep:' || cu.Reputation ||
                       ' AvgScore:' || CAST(ROUND(uts.avg_question_score,2) AS TEXT))
        END                                   AS performance_label
    FROM combined_users cu
    LEFT JOIN user_tag_stats uts 
           ON uts.user_id = cu.user_id
    LEFT JOIN user_answer_counts uac 
           ON uac.user_id = cu.user_id
    LEFT JOIN recent_activity ra 
           ON ra.uid = cu.user_id
    LEFT JOIN duplicate_links dl 
           ON dl.question_id = (
               SELECT MIN(p.Id) 
               FROM Posts p 
               WHERE p.OwnerUserId = cu.user_id 
                 AND p.PostTypeId = 1
           )
    GROUP BY
        cu.user_id,
        cu.display_name,
        cu.Reputation,
        cu.gold_badge_cnt,
        uts.question_cnt,
        uts.avg_question_score,
        uac.answer_cnt,
        ra.last_activity_dt,
        uts.tag_list,
        dl.duplicate_of_id
)

SELECT *
FROM final_result
WHERE reputation_rank <= 100
ORDER BY reputation_rank;