-- {"query": "3490.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2493} 

WITH 
    -- Aggregate post statistics per user
    usr_posts AS (
        SELECT 
            u.Id                               AS user_id,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id)                        AS total_posts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
            MAX(p.CreationDate)               AS last_post_date
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    -- Badge counts per user
    usr_badges AS (
        SELECT 
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- Tag usage per user (explode Tags column)
    usr_tags AS (
        SELECT 
            p.OwnerUserId                               AS user_id,
            UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag,
            COUNT(*)                                    AS tag_cnt
        FROM Posts p
        WHERE p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><'))
    ),

    -- Top tag per user using a window function
    top_tags AS (
        SELECT 
            ut.user_id,
            ut.tag,
            ut.tag_cnt,
            ROW_NUMBER() OVER (PARTITION BY ut.user_id ORDER BY ut.tag_cnt DESC) AS rn
        FROM usr_tags ut
    ),

    -- Recent votes (last 30 days) for score delta calculations
    recent_votes AS (
        SELECT 
            v.PostId,
            v.VoteTypeId,
            v.CreationDate,
            v.UserId AS voter_id
        FROM Votes v
        WHERE v.CreationDate >= (CURRENT_DATE - INTERVAL '30 days')
    ),

    -- Vote statistics per user based on their posts
    usr_vote_stats AS (
        SELECT 
            p.OwnerUserId               AS user_id,
            COUNT(rv.VoteTypeId)        AS recent_vote_cnt,
            SUM(CASE 
                    WHEN rv.VoteTypeId = 2 THEN 1   -- UpMod
                    WHEN rv.VoteTypeId = 3 THEN -1  -- DownMod
                    ELSE 0
                END)                     AS recent_score_delta
        FROM Posts p
        LEFT JOIN recent_votes rv
               ON rv.PostId = p.Id
        GROUP BY p.OwnerUserId
    )

SELECT 
    up.user_id,
    up.DisplayName,
    up.Reputation,
    up.total_posts,
    up.questions,
    up.answers,
    ROUND(up.avg_score::numeric, 2)                     AS avg_score,
    COALESCE(ub.gold, 0)                               AS gold_badges,
    COALESCE(ub.silver, 0)                             AS silver_badges,
    COALESCE(ub.bronze, 0)                             AS bronze_badges,
    -- number of questions that have an accepted answer (correlated sub‑query)
    (SELECT COUNT(*)
       FROM Posts q
      WHERE q.OwnerUserId = up.user_id
        AND q.PostTypeId = 1
        AND q.AcceptedAnswerId IS NOT NULL)            AS questions_with_accepted,
    CASE WHEN tt.rn = 1 THEN tt.tag ELSE NULL END      AS top_tag,
    CASE WHEN tt.rn = 1 THEN tt.tag_cnt ELSE NULL END  AS top_tag_count,
    COALESCE(uvs.recent_vote_cnt, 0)                   AS recent_vote_cnt,
    COALESCE(uvs.recent_score_delta, 0)                AS recent_score_delta,
    CASE 
        WHEN up.last_post_date IS NULL THEN 'Never posted'
        ELSE TO_CHAR(up.last_post_date, 'YYYY‑MM‑DD')
    END                                                AS last_post_date
FROM usr_posts up
LEFT JOIN usr_badges ub
       ON ub.UserId = up.user_id
LEFT JOIN top_tags tt
       ON tt.user_id = up.user_id AND tt.rn = 1
LEFT JOIN usr_vote_stats uvs
       ON uvs.user_id = up.user_id

UNION ALL

-- A summary row with totals across all users
SELECT 
    NULL,
    'TOTAL'                                            AS display_name,
    SUM(up.Reputation)                                 AS reputation,
    SUM(up.total_posts)                                AS total_posts,
    SUM(up.questions)                                  AS total_questions,
    SUM(up.answers)                                    AS total_answers,
    ROUND(AVG(up.avg_score)::numeric, 2)               AS avg_score,
    SUM(COALESCE(ub.gold, 0))                          AS gold_badges,
    SUM(COALESCE(ub.silver, 0))                        AS silver_badges,
    SUM(COALESCE(ub.bronze, 0))                        AS bronze_badges,
    NULL                                               AS questions_with_accepted,
    NULL                                               AS top_tag,
    NULL                                               AS top_tag_count,
    SUM(COALESCE(uvs.recent_vote_cnt, 0))              AS recent_vote_cnt,
    SUM(COALESCE(uvs.recent_score_delta, 0))           AS recent_score_delta,
    NULL                                               AS last_post_date
FROM usr_posts up
LEFT JOIN usr_badges ub   ON ub.UserId = up.user_id
LEFT JOIN usr_vote_stats uvs ON uvs.user_id = up.user_id;
