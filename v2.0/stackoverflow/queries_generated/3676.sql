-- {"query": "3676.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2048} 

/*  Comprehensive performance‑benchmark query over the StackOverflow schema  */
WITH 
/* 1️⃣ Aggregate post counts and recent activity per user */
usr_posts AS (
    SELECT 
        u.Id                           AS user_id,
        u.DisplayName                  AS display_name,
        COUNT(p.Id)                    AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_cnt,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_cnt,
        MAX(p.CreationDate)            AS last_post_dt,
        COALESCE(MAX(p.Score),0)       AS max_post_score
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

/* 2️⃣ Concatenate badge names and find the most recent badge per user */
usr_badges AS (
    SELECT 
        b.UserId                              AS user_id,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Name IS NOT NULL) AS badge_list,
        MAX(b.Date)                           AS last_badge_dt,
        COUNT(*)                              AS badge_cnt
    FROM Badges b
    GROUP BY b.UserId
),

/* 3️⃣ Derive the top 3 tags each user has used in questions (via a window function) */
usr_top_tags AS (
    SELECT 
        p.OwnerUserId                         AS user_id,
        REPLACE(REPLACE(tag_raw, '<', ''), '>', '') AS tag_name,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY tag_usage DESC) AS tag_rank
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '><') AS tag_raw
    JOIN Tags t
        ON t.TagName = REPLACE(REPLACE(tag_raw, '<', ''), '>', '')
    WHERE p.PostTypeId = 1               -- only questions
    GROUP BY p.OwnerUserId, tag_raw
    HAVING COUNT(*) > 0
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) <= 3
),

/* 4️⃣ Recent vote activity (last 30 days) with a correlated sub‑query to fetch the vote‑type name */
recent_votes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        vt.Name               AS vote_type_name,
        v.CreationDate,
        p.OwnerUserId         AS user_id
    FROM Votes v
    JOIN Posts p
        ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt
        ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '30 days')
),

/* 5️⃣ Users with no activity in the last year (NULL‑logic + NOT EXISTS) */
inactive_users AS (
    SELECT u.Id AS user_id
    FROM Users u
    WHERE NOT EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '365 days')
    )
    AND NOT EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.UserId = u.Id
          AND c.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '365 days')
    )
),

/* 6️⃣ Union of two derived sets: users with high reputation vs. low reputation   */
high_low_rep AS (
    SELECT u.Id AS user_id,
           u.Reputation,
           CASE 
               WHEN u.Reputation >= 20000 THEN 'HIGH'
               WHEN u.Reputation <= 1000  THEN 'LOW'
               ELSE 'MEDIUM'
           END AS rep_category
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),

/* 7️⃣ Correlated sub‑query to compute the average score of a user's answers */
answer_score_avg AS (
    SELECT 
        u.Id AS user_id,
        (SELECT AVG(p.Score)::numeric(10,2)
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
           AND p.PostTypeId = 2) AS avg_answer_score
    FROM Users u
)

-- Final result set assembling everything with outer joins, window functions, set operators, and complex predicates
SELECT 
    up.user_id,
    up.display_name,
    up.total_posts,
    up.question_cnt,
    up.answer_cnt,
    up.last_post_dt,
    ub.badge_list,
    ub.badge_cnt,
    ub.last_badge_dt,
    COALESCE(asa.avg_answer_score, 0)                     AS avg_answer_score,
    hr.rep_category,
    rv.vote_type_name,
    rv.CreationDate                                      AS recent_vote_dt,
    STRING_AGG(DISTINCT ut.tag_name, ', ') 
        FILTER (WHERE ut.tag_rank <= 3)                  AS top_3_tags,
    CASE 
        WHEN iu.user_id IS NOT NULL THEN 'INACTIVE'
        ELSE 'ACTIVE'
    END                                                  AS activity_status,
    ROW_NUMBER() OVER (PARTITION BY up.user_id ORDER BY rv.CreationDate DESC) 
                                                         AS recent_vote_rank
FROM usr_posts up
LEFT JOIN usr_badges ub
    ON ub.user_id = up.user_id
LEFT JOIN answer_score_avg asa
    ON asa.user_id = up.user_id
LEFT JOIN high_low_rep hr
    ON hr.user_id = up.user_id
LEFT JOIN recent_votes rv
    ON rv.user_id = up.user_id
LEFT JOIN usr_top_tags ut
    ON ut.user_id = up.user_id
LEFT JOIN inactive_users iu
    ON iu.user_id = up.user_id
GROUP BY 
    up.user_id, up.display_name, up.total_posts, up.question_cnt,
    up.answer_cnt, up.last_post_dt, ub.badge_list, ub.badge_cnt,
    ub.last_badge_dt, asa.avg_answer_score, hr.rep_category,
    rv.vote_type_name, rv.CreationDate, iu.user_id
HAVING COUNT(rv.VoteTypeId) > 0                           -- keep only users with at least one recent vote
ORDER BY up.total_posts DESC, up.user_id
LIMIT 100
UNION ALL
/* 8️⃣ Supplementary set: all completely inactive users with zero posts/badges */
SELECT 
    iu.user_id,
    u.DisplayName,
    0                              AS total_posts,
    0                              AS question_cnt,
    0                              AS answer_cnt,
    NULL                           AS last_post_dt,
    NULL                           AS badge_list,
    0                              AS badge_cnt,
    NULL                           AS last_badge_dt,
    NULL                           AS avg_answer_score,
    'LOW'                          AS rep_category,
    NULL                           AS vote_type_name,
    NULL                           AS recent_vote_dt,
    NULL                           AS top_3_tags,
    'INACTIVE'                     AS activity_status,
    NULL                           AS recent_vote_rank
FROM inactive_users iu
JOIN Users u ON u.Id = iu.user_id
ORDER BY user_id
LIMIT 50;
