-- {"query": "3031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2314} 

/*  Complex benchmark query over the StackOverflow schema  */
WITH 
/*--------------------------------------------------------------
   1. Aggregate posts per user (questions and answers) with
      total score, average score, first and last activity dates.
--------------------------------------------------------------*/
user_posts AS (
    SELECT 
        p.OwnerUserId                           AS user_id,
        COUNT(*)                                AS post_cnt,
        SUM(p.Score)                            AS total_score,
        AVG(p.Score)                            AS avg_score,
        MIN(p.CreationDate)                     AS first_post_dt,
        MAX(p.LastActivityDate)                 AS last_activity_dt
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/*--------------------------------------------------------------
   2. Badge statistics per user, weighted by class (gold>silver>bronze)
--------------------------------------------------------------*/
user_badges AS (
    SELECT 
        b.UserId                                 AS user_id,
        COUNT(*)                                 AS badge_cnt,
        SUM(CASE b.Class WHEN 1 THEN 3 
                         WHEN 2 THEN 2 
                         ELSE 1 END)          AS badge_weight
    FROM Badges b
    GROUP BY b.UserId
),

/*--------------------------------------------------------------
   3. Net vote tally per user (upvotes - downvotes) across all posts
--------------------------------------------------------------*/
user_votes AS (
    SELECT 
        p.OwnerUserId                           AS user_id,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1      -- UpMod
                 WHEN v.VoteTypeId = 3 THEN -1     -- DownMod
                 ELSE 0 END)                     AS net_votes
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND v.VoteTypeId IN (2,3)
    GROUP BY p.OwnerUserId
),

/*--------------------------------------------------------------
   4. Latest comment date per user (including users with no comments)
--------------------------------------------------------------*/
user_comments AS (
    SELECT 
        u.Id                                    AS user_id,
        MAX(c.CreationDate)                     AS last_comment_dt
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),

/*--------------------------------------------------------------
   5. Extract first tag from each question and count its usage
--------------------------------------------------------------*/
tag_usage AS (
    SELECT 
        TRIM(BOTH '<>' FROM split_part(p.Tags, '><', 1)) AS tag,
        COUNT(*)                                         AS tag_q_cnt
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
      AND p.Tags IS NOT NULL
    GROUP BY TRIM(BOTH '<>' FROM split_part(p.Tags, '><', 1))
),

/*--------------------------------------------------------------
   6. Detect if a user has authored a post that is marked as a duplicate
--------------------------------------------------------------*/
user_dupes AS (
    SELECT DISTINCT 
        p.OwnerUserId                AS user_id,
        1                           AS has_duplicate
    FROM Posts p
    JOIN PostLinks pl 
        ON pl.PostId = p.Id
       AND pl.LinkTypeId = 3        -- Duplicate link
    WHERE p.OwnerUserId IS NOT NULL
),

/*--------------------------------------------------------------
   7. Recent activity (post or comment) per user – used for ranking
--------------------------------------------------------------*/
user_recent_activity AS (
    SELECT 
        u.Id                                AS user_id,
        GREATEST(
            COALESCE(up.last_activity_dt, '1970-01-01'::timestamp),
            COALESCE(uc.last_comment_dt, '1970-01-01'::timestamp)
        )                                   AS most_recent_dt
    FROM Users u
    LEFT JOIN user_posts up   ON up.user_id = u.Id
    LEFT JOIN user_comments uc ON uc.user_id = u.Id
),

/*--------------------------------------------------------------
   8. Combine all per‑user aggregates, handling missing rows with NULL logic
--------------------------------------------------------------*/
user_summary AS (
    SELECT 
        u.Id                                          AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(up.post_cnt,0)                       AS post_cnt,
        COALESCE(up.total_score,0)                    AS total_score,
        COALESCE(up.avg_score,0)                      AS avg_score,
        COALESCE(ub.badge_cnt,0)                      AS badge_cnt,
        COALESCE(ub.badge_weight,0)                   AS badge_weight,
        COALESCE(uv.net_votes,0)                      AS net_votes,
        uc.last_comment_dt,
        COALESCE(ud.has_duplicate,0)                  AS has_duplicate,
        ura.most_recent_dt,
        /* Composite activity score for ranking */
        (u.Reputation * 0.6
         + COALESCE(ub.badge_weight,0) * 100
         + COALESCE(uv.net_votes,0) * 10
         + COALESCE(up.total_score,0) * 0.5)          AS activity_score
    FROM Users u
    LEFT JOIN user_posts up      ON up.user_id = u.Id
    LEFT JOIN user_badges ub    ON ub.user_id = u.Id
    LEFT JOIN user_votes uv     ON uv.user_id = u.Id
    LEFT JOIN user_comments uc  ON uc.user_id = u.Id
    LEFT JOIN user_dupes ud     ON ud.user_id = u.Id
    LEFT JOIN user_recent_activity ura ON ura.user_id = u.Id
    WHERE u.CreationDate < (CURRENT_DATE - INTERVAL '1 year')
      AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
)

SELECT 
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.post_cnt,
    us.total_score,
    us.avg_score,
    us.badge_cnt,
    us.badge_weight,
    us.net_votes,
    us.last_comment_dt,
    us.has_duplicate,
    us.most_recent_dt,
    /* Rank users by the composite activity_score, ties broken by Reputation */
    ROW_NUMBER() OVER (ORDER BY us.activity_score DESC, us.Reputation DESC) AS rank_by_activity
FROM user_summary us
WHERE us.activity_score > 0
ORDER BY rank_by_activity
LIMIT 100

/* --------------------------------------------------------------
   UNION ALL a dummy row set to exercise set operators and NULL handling
   -------------------------------------------------------------- */
UNION ALL
SELECT 
    NULL::int        AS user_id,
    NULL::varchar    AS DisplayName,
    NULL::int        AS Reputation,
    0                AS post_cnt,
    0                AS total_score,
    0                AS avg_score,
    0                AS badge_cnt,
    0                AS badge_weight,
    0                AS net_votes,
    NULL::timestamp  AS last_comment_dt,
    0                AS has_duplicate,
    NULL::timestamp  AS most_recent_dt,
    0                AS rank_by_activity
WHERE FALSE;
