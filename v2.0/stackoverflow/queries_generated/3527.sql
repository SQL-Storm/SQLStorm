-- {"query": "3527.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2242} 

/*======================================================================
  Performance‑benchmarking query – combines CTEs, window functions,
  outer joins, correlated subqueries, set operators, string ops and
  NULL logic.
======================================================================*/

WITH
--------------------------------------------------------------------------------
-- 1. Aggregated post stats per user (questions, answers, avg score, tag diversity)
user_post_stats AS (
    SELECT
        u.Id                                     AS user_id,
        u.DisplayName,
        COUNT(p.Id)                               AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_cnt,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_cnt,
        AVG(p.Score)                              AS avg_score,
        /* distinct tag count for all questions owned by the user */
        COALESCE(
            (
                SELECT COUNT(DISTINCT unnest_tag)
                FROM (
                    SELECT unnest(string_to_array(
                        TRIM(BOTH '<>' FROM p.Tags), '><')) AS unnest_tag
                    FROM Posts p
                    WHERE p.OwnerUserId = u.Id
                      AND p.PostTypeId = 1
                      AND p.Tags IS NOT NULL
                ) t
            ), 0)                                 AS distinct_tag_cnt
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

--------------------------------------------------------------------------------
-- 2. Badge aggregation per user
user_badge_stats AS (
    SELECT
        b.UserId                                 AS user_id,
        COUNT(*)                                 AS badge_total,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
        MAX(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS has_tag_badge
    FROM Badges b
    GROUP BY b.UserId
),

--------------------------------------------------------------------------------
-- 3. Vote totals per post (used later for correlated sub‑query)
post_vote_totals AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    GROUP BY v.PostId
),

--------------------------------------------------------------------------------
-- 4. Close‑vote counts per question (via PostHistory)
question_close_counts AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS close_votes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS reopen_votes
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11)
    GROUP BY ph.PostId
),

--------------------------------------------------------------------------------
-- 5. Top‑scoring question per user (window function)
top_question_per_user AS (
    SELECT
        p.OwnerUserId                AS user_id,
        p.Id                         AS question_id,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY p.Score DESC NULLS LAST,
                                    p.CreationDate) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),

--------------------------------------------------------------------------------
-- 6. Users who have badges but no posts (for the UNION ALL branch)
badge_only_users AS (
    SELECT DISTINCT
        ub.user_id,
        u.DisplayName
    FROM user_badge_stats ub
    LEFT JOIN user_post_stats up
           ON up.user_id = ub.user_id
    JOIN Users u
           ON u.Id = ub.user_id
    WHERE up.user_id IS NULL
)

--------------------------------------------------------------------------------
-- Main result set – active users (with posts) -----------------------------------
SELECT
    ups.user_id,
    ups.DisplayName,
    ups.total_posts,
    ups.question_cnt,
    ups.answer_cnt,
    ROUND(ups.avg_score,2)                               AS avg_score,
    ups.distinct_tag_cnt,
    COALESCE(ubs.badge_total,0)                          AS badge_total,
    COALESCE(ubs.gold_cnt,0)                             AS gold_badges,
    COALESCE(ubs.silver_cnt,0)                           AS silver_badges,
    COALESCE(ubs.bronze_cnt,0)                           AS bronze_badges,
    CASE WHEN ubc.close_votes IS NULL THEN 0
         ELSE ubc.close_votes END                       AS total_close_votes,
    CASE WHEN ubc.reopen_votes IS NULL THEN 0
         ELSE ubc.reopen_votes END                     AS total_reopen_votes,
    /* accepted‑answer ratio – correlated sub‑query */
    (SELECT
         ROUND( CAST(cnt_accepted AS numeric) /
                NULLIF(cnt_answers,0), 3)
     FROM (
         SELECT
             COUNT(*) FILTER (WHERE a.Id IS NOT NULL)        AS cnt_accepted,
             COUNT(*) FILTER (WHERE a.PostTypeId = 2)         AS cnt_answers
         FROM Posts q
         LEFT JOIN Posts a
                ON a.ParentId = q.Id
               AND a.PostTypeId = 2
               AND a.Id = q.AcceptedAnswerId
         WHERE q.OwnerUserId = ups.user_id
           AND q.PostTypeId = 1
     ) sub)                                              AS accepted_answer_ratio,
    /* top question title – safe NULL handling */
    COALESCE(tq.Title, '(none)')                         AS top_question_title,
    COALESCE(tq.Score, 0)                                AS top_question_score
FROM user_post_stats ups
LEFT JOIN user_badge_stats ubs
       ON ubs.user_id = ups.user_id
LEFT JOIN question_close_counts ubc
       ON ubc.PostId = (
            SELECT q.Id
            FROM Posts q
            WHERE q.OwnerUserId = ups.user_id
              AND q.PostTypeId = 1
              AND q.AcceptedAnswerId IS NOT NULL
            ORDER BY q.Score DESC
            LIMIT 1
          )
LEFT JOIN top_question_per_user tq
       ON tq.user_id = ups.user_id
      AND tq.rn = 1
WHERE ups.user_id IS NOT NULL

UNION ALL

-- ==============================================================================
-- Users with badges but zero posts (to stress outer‑join/NULL handling)
-- ==============================================================================
SELECT
    bou.user_id,
    bou.DisplayName,
    0                         AS total_posts,
    0                         AS question_cnt,
    0                         AS answer_cnt,
    NULL                      AS avg_score,
    0                         AS distinct_tag_cnt,
    COALESCE(ubs.badge_total,0) AS badge_total,
    COALESCE(ubs.gold_cnt,0)    AS gold_badges,
    COALESCE(ubs.silver_cnt,0)  AS silver_badges,
    COALESCE(ubs.bronze_cnt,0)  AS bronze_badges,
    0                           AS total_close_votes,
    0                           AS total_reopen_votes,
    NULL                        AS accepted_answer_ratio,
    '(no posts)'                AS top_question_title,
    0                           AS top_question_score
FROM badge_only_users bou
LEFT JOIN user_badge_stats ubs
       ON ubs.user_id = bou.user_id
ORDER BY total_posts DESC, badge_total DESC, user_id;
