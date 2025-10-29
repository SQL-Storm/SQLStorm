-- {"query": "3167.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3242} 

/*  Benchmark query combining CTEs, window functions, outer joins, correlated sub‑queries, 
    set operators, string manipulation and NULL handling.  */
WITH
    /* 1. Rank users by reputation */
    ranked_users AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
        FROM Users u
        WHERE u.Reputation IS NOT NULL
    ),

    /* 2. Aggregate badge counts per user, using filtered aggregates */
    badge_counts AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze,
            COUNT(*)                         AS total_badges
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* 3. Compute per‑user, per‑tag answer score (answers only) */
    user_tag_scores AS (
        SELECT
            p.OwnerUserId                              AS user_id,
            UNNEST(string_to_array(
                REGEXP_REPLACE(p.Tags, '^<|>$', ''),   -- strip leading/trailing <>
                '><'
            ))                                         AS tag,
            SUM(p.Score)                               AS tag_score,
            COUNT(*)                                   AS answer_cnt
        FROM Posts p
        WHERE p.PostTypeId = 2                         -- answers
        GROUP BY p.OwnerUserId, tag
    ),

    /* 4. Rank tags per user by tag_score */
    top_user_tags AS (
        SELECT
            uts.user_id,
            uts.tag,
            uts.tag_score,
            ROW_NUMBER() OVER (PARTITION BY uts.user_id ORDER BY uts.tag_score DESC) AS tag_rank
        FROM user_tag_scores uts
    ),

    /* 5. Most recent activity dates per user (outer joins expose missing data) */
    recent_activity AS (
        SELECT
            u.Id                             AS user_id,
            MAX(p.CreationDate)              AS last_post_dt,
            MAX(v.CreationDate)              AS last_vote_dt,
            MAX(c.CreationDate)              AS last_comment_dt
        FROM Users u
        LEFT JOIN Posts    p ON p.OwnerUserId    = u.Id
        LEFT JOIN Votes    v ON v.UserId         = u.Id
        LEFT JOIN Comments c ON c.UserId         = u.Id
        GROUP BY u.Id
    ),

    /* 6. Closed‑duplicate history (correlated JSON extraction) */
    closed_duplicates AS (
        SELECT
            ph.PostId,
            ph.CreationDate,
            ph.Comment::smallint                     AS close_reason_id,
            jsonb_array_elements_text(ph.Text)::int AS duplicate_of
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10               -- Post Closed
          AND ph.Comment::int IN (101,102)            -- duplicate reasons
    ),

    /* 7. Duplicate link rows (LinkType 3 = Duplicate) */
    duplicate_links AS (
        SELECT
            pl.PostId,
            pl.RelatedPostId,
            lt.Name AS link_type_name
        FROM PostLinks pl
        JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
        WHERE lt.Id = 3                               -- Duplicate
    ),

    /* 8. Combine close history with link data (LEFT JOIN to keep rows without link) */
    closed_info AS (
        SELECT
            cd.PostId,
            cd.duplicate_of,
            dl.RelatedPostId            AS duplicate_target,
            cd.close_reason_id
        FROM closed_duplicates cd
        LEFT JOIN duplicate_links dl ON dl.PostId = cd.PostId
    )

/* ============================= MAIN SELECT ============================= */
SELECT
    ru.Id                               AS user_id,
    ru.DisplayName,
    ru.Reputation,
    COALESCE(bc.gold,0)                AS gold_badges,
    COALESCE(bc.silver,0)              AS silver_badges,
    COALESCE(bc.bronze,0)              AS bronze_badges,
    COALESCE(bc.total_badges,0)        AS total_badges,
    COALESCE(ra.last_post_dt,
             TIMESTAMP '1970-01-01')    AS last_post_date,
    COALESCE(ra.last_vote_dt,
             TIMESTAMP '1970-01-01')    AS last_vote_date,
    COALESCE(ra.last_comment_dt,
             TIMESTAMP '1970-01-01')    AS last_comment_date,

    /* concatenate top 1 and top 3 tags */
    STRING_AGG(DISTINCT CASE WHEN tut.tag_rank = 1 THEN tut.tag END, ', ') 
        FILTER (WHERE tut.tag_rank = 1)                     AS top_tag,
    STRING_AGG(DISTINCT CASE WHEN tut.tag_rank <= 3 THEN tut.tag END, ', ')
        FILTER (WHERE tut.tag_rank <= 3)                    AS top_3_tags,

    /* status derived from the most recent question (correlated sub‑query) */
    CASE
        WHEN ci.close_reason_id IS NOT NULL
            THEN 'Closed: '||COALESCE(crt.Name,'Unknown')
        ELSE 'Open'
    END                              AS status,

    /* derived scalar sub‑queries */
    (SELECT COUNT(*) FROM Posts p
        WHERE p.OwnerUserId = ru.Id AND p.PostTypeId = 1) AS questions_asked,
    (SELECT COUNT(*) FROM Posts p
        WHERE p.OwnerUserId = ru.Id AND p.PostTypeId = 2) AS answers_given,
    ROUND(
        (SELECT SUM(p.Score) FROM Posts p
            WHERE p.OwnerUserId = ru.Id AND p.PostTypeId = 2)::numeric
        / NULLIF(
            (SELECT COUNT(*) FROM Posts p
                WHERE p.OwnerUserId = ru.Id AND p.PostTypeId = 2),0),2
    )                                 AS avg_answer_score
FROM ranked_users ru
LEFT JOIN badge_counts   bc ON bc.UserId        = ru.Id
LEFT JOIN recent_activity ra ON ra.user_id      = ru.Id
LEFT JOIN top_user_tags   tut ON tut.user_id    = ru.Id
LEFT JOIN closed_info     ci  ON ci.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = ru.Id
          AND p.PostTypeId = 1                -- questions
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN CloseReasonTypes crt ON crt.Id = ci.close_reason_id::smallint
WHERE ru.rn <= 100
GROUP BY
    ru.Id, ru.DisplayName, ru.Reputation,
    bc.gold, bc.silver, bc.bronze, bc.total_badges,
    ra.last_post_dt, ra.last_vote_dt, ra.last_comment_dt,
    ci.close_reason_id, crt.Name
ORDER BY ru.Reputation DESC
LIMIT 100

UNION ALL

/* ========================= AGGREGATE ROW ========================= */
SELECT
    NULL               AS user_id,
    'Aggregate'        AS DisplayName,
    NULL               AS Reputation,
    SUM(COALESCE(bc.gold,0))   AS gold_badges,
    SUM(COALESCE(bc.silver,0)) AS silver_badges,
    SUM(COALESCE(bc.bronze,0)) AS bronze_badges,
    SUM(COALESCE(bc.total_badges,0)) AS total_badges,
    MAX(ra.last_post_dt)       AS last_post_date,
    MAX(ra.last_vote_dt)       AS last_vote_date,
    MAX(ra.last_comment_dt)    AS last_comment_date,
    NULL, NULL, NULL, NULL, NULL, NULL
FROM ranked_users ru
LEFT JOIN badge_counts   bc ON bc.UserId = ru.Id
LEFT JOIN recent_activity ra ON ra.user_id = ru.Id
WHERE ru.rn <= 100;
