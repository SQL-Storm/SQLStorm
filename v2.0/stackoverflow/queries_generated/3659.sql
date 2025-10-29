-- {"query": "3659.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2870} 

/* -------------------------------------------------
   Performance‑benchmarking query for the StackOverflow schema
   ------------------------------------------------- */
WITH
/* ------------------------------------------------------------------
   1. Aggregate post statistics per user (questions vs. answers)
   ------------------------------------------------------------------ */
user_posts AS (
    SELECT
        u.Id                                            AS user_id,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)    AS question_cnt,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)    AS answer_cnt,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)   AS avg_question_score,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)   AS avg_answer_score,
        MAX(p.CreationDate)                           AS last_post_dt
    FROM   Users u
    LEFT   JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP  BY u.Id
),

/* ------------------------------------------------------------------
   2. Total votes (up‑ and down‑votes) received on a user’s posts
   ------------------------------------------------------------------ */
user_votes AS (
    SELECT
        u.Id                                             AS user_id,
        COALESCE(SUM(vote_cnt.cnt),0)                    AS total_votes_received
    FROM   Users u
    LEFT   JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(v.Id) AS cnt
        FROM   Posts p
        JOIN   Votes v ON v.PostId = p.Id
        WHERE  v.VoteTypeId IN (2,3)                     -- up‑ and down‑votes
        GROUP  BY p.OwnerUserId
    ) vote_cnt ON vote_cnt.OwnerUserId = u.Id
    GROUP  BY u.Id
),

/* ------------------------------------------------------------------
   3. Badge aggregates and the most recent badge per user
   ------------------------------------------------------------------ */
user_badge_stats AS (
    SELECT
        u.Id                     AS user_id,
        COUNT(b.Id)              AS badge_cnt,
        MAX(b.Date)              AS latest_badge_dt
    FROM   Users u
    LEFT   JOIN Badges b ON b.UserId = u.Id
    GROUP  BY u.Id
),
latest_badge AS (
    SELECT
        b.UserId,
        b.Name                     AS latest_badge_name,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM   Badges b
),

/* ------------------------------------------------------------------
   4. Distinct tag list used by a user in his/her questions
   ------------------------------------------------------------------ */
user_tags AS (
    SELECT
        u.Id                                   AS user_id,
        STRING_AGG(DISTINCT t.TagName, ', ')   AS tag_list
    FROM   Users u
    JOIN   Posts p
           ON p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    CROSS  JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
    ) AS tt
    JOIN   Tags t
           ON t.TagName = tt.tag
    GROUP  BY u.Id
),

/* ------------------------------------------------------------------
   5. Bool flag: has the user ever performed a close vote (via PostHistory)?
   ------------------------------------------------------------------ */
user_close_flag AS (
    SELECT
        u.Id                                         AS user_id,
        EXISTS (
            SELECT 1
            FROM   PostHistory ph
            WHERE  ph.PostHistoryTypeId = 10          -- Post Closed
            AND    ph.UserId = u.Id
        )                                            AS has_closed_any_question
    FROM   Users u
),

/* ------------------------------------------------------------------
   6. Correlated sub‑query: most recent date the user authored an accepted answer
   ------------------------------------------------------------------ */
user_recent_accepted AS (
    SELECT
        u.Id                                                   AS user_id,
        (
            SELECT MAX(p2.CreationDate)
            FROM   Posts p2
            WHERE  p2.OwnerUserId = u.Id
            AND    p2.PostTypeId = 2                               -- answer
            AND    EXISTS (
                     SELECT 1
                     FROM   Posts q
                     WHERE  q.Id = p2.ParentId
                     AND    q.AcceptedAnswerId = p2.Id
                 )
        )                                                       AS most_recent_accepted_answer_dt
    FROM   Users u
)

SELECT
    u.Id                                       AS user_id,
    u.DisplayName,
    u.Reputation,
    up.question_cnt,
    up.answer_cnt,
    up.avg_question_score,
    up.avg_answer_score,
    uv.total_votes_received,
    ub.badge_cnt,
    lb.latest_badge_name,
    ut.tag_list,
    uc.has_closed_any_question,
    RANK() OVER (ORDER BY u.Reputation DESC)   AS reputation_rank,
    ura.most_recent_accepted_answer_dt,
    COALESCE(up.last_post_dt, u.CreationDate) AS last_activity_dt
FROM   Users u
LEFT   JOIN user_posts        up   ON up.user_id   = u.Id
LEFT   JOIN user_votes        uv   ON uv.user_id   = u.Id
LEFT   JOIN user_badge_stats  ub   ON ub.user_id   = u.Id
LEFT   JOIN latest_badge       lb   ON lb.UserId    = u.Id AND lb.rn = 1
LEFT   JOIN user_tags         ut   ON ut.user_id   = u.Id
LEFT   JOIN user_close_flag   uc   ON uc.user_id   = u.Id
LEFT   JOIN user_recent_accepted ura ON ura.user_id = u.Id
WHERE  u.Reputation > 0

UNION ALL

/* ------------------------------------------------------------------
   Dummy row for benchmarking the empty‑set handling path
   ------------------------------------------------------------------ */
SELECT
    0                                          AS user_id,
    'Anonymous'                                AS DisplayName,
    0                                          AS Reputation,
    0,0,NULL,NULL,0,0,NULL,NULL,FALSE,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Reputation = 0)

ORDER BY reputation_rank NULLS LAST, user_id;
