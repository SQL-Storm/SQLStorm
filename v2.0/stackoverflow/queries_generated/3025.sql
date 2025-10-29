-- {"query": "3025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2529} 

/*  ==============================================================
    Benchmark query – mixes CTEs, window functions, outer joins,
    correlated subqueries, set operators, string handling and NULL logic
   ============================================================== */

WITH
/* -----------------------------------------------------------------
   1.  Aggregate user reputation, badge counts and voting score
   ----------------------------------------------------------------- */
usr_agg AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id)                   AS badge_cnt,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
        COALESCE(SUM(
            CASE v.VoteTypeId
                 WHEN 2 THEN  1      -- upvote
                 WHEN 3 THEN -1      -- downvote
                 ELSE 0
            END),0)                              AS vote_score,
        MAX(p.CreationDate)                    AS last_post_dt
    FROM Users u
    LEFT JOIN Badges b           ON b.UserId = u.Id
    LEFT JOIN Posts p            ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v            ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* -----------------------------------------------------------------
   2.  Most recent activity per user (comments, post‑history, votes)
   ----------------------------------------------------------------- */
usr_last_act AS (
    SELECT
        u.Id                                   AS user_id,
        GREATEST(
            COALESCE(MAX(c.CreationDate),   TIMESTAMP '1970-01-01'),
            COALESCE(MAX(ph.CreationDate),  TIMESTAMP '1970-01-01'),
            COALESCE(MAX(v.CreationDate),   TIMESTAMP '1970-01-01')
        )                                      AS last_activity_dt
    FROM Users u
    LEFT JOIN Comments   c  ON c.UserId   = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Votes      v  ON v.UserId   = u.Id
    GROUP BY u.Id
),

/* -----------------------------------------------------------------
   3.  Tag statistics (usage, total score, top contributors)
   ----------------------------------------------------------------- */
tag_stats AS (
    SELECT
        t.TagName,
        t.Count                              AS tag_use_cnt,
        COALESCE(SUM(p.Score),0)             AS total_score,
        COUNT(DISTINCT p.Id)                 AS question_cnt,
        STRING_AGG(DISTINCT u.DisplayName, ', ')
            FILTER (WHERE u.Id IS NOT NULL) AS top_contributors
    FROM Tags t
    LEFT JOIN PostLinks pl
           ON pl.RelatedPostId = t.WikiPostId
    LEFT JOIN Posts p
           ON p.Id = pl.PostId AND p.PostTypeId = 1          -- only questions
    LEFT JOIN Users u
           ON u.Id = p.OwnerUserId
    GROUP BY t.TagName, t.Count
),

/* -----------------------------------------------------------------
   4.  Find questions that were closed as duplicates (JSON parsing)
   ----------------------------------------------------------------- */
dup_closed AS (
    SELECT
        ph.PostId                                 AS question_id,
        jsonb_array_elements_text(ph.Text::jsonb -> 'OriginalQuestionIds')::int
                                                  AS duplicate_of
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10                 -- Post Closed
      AND ph.Comment ~ '^\d+$'                      -- comment stores close‑reason id
      AND (ph.Text::jsonb) ? 'OriginalQuestionIds'  -- JSON contains duplicates
),

/* -----------------------------------------------------------------
   5.  Rank users by reputation and badge count (window function)
   ----------------------------------------------------------------- */
ranked_users AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.badge_cnt DESC) AS rk
    FROM usr_agg ua
)

-- =================================================================
-- Final result set (union of two “report” sections, same column list)
-- =================================================================
SELECT
    ru.user_id,
    ru.DisplayName,
    ru.Reputation,
    ru.badge_cnt,
    ru.gold_cnt,
    ru.silver_cnt,
    ru.bronze_cnt,
    ru.vote_score,
    ru.last_post_dt,
    ula.last_activity_dt,
    CASE WHEN dc.question_id IS NOT NULL THEN 1 ELSE 0 END AS is_closed_duplicate,
    NULL::varchar   AS tag_name,
    NULL::int       AS tag_use_cnt,
    NULL::int       AS total_score,
    NULL::int       AS question_cnt,
    NULL::varchar   AS top_contributors,
    ru.rk           AS rank_position
FROM ranked_users ru
LEFT JOIN usr_last_act ula          ON ula.user_id = ru.user_id
LEFT JOIN LATERAL (
        SELECT dc.question_id
        FROM dup_closed dc
        WHERE dc.question_id = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = ru.user_id
              AND p.PostTypeId = 1               -- questions only
            ORDER BY p.CreationDate DESC
            LIMIT 1
        )
        LIMIT 1
) dc ON TRUE
WHERE ru.rk <= 100                                         -- top‑100 users

UNION ALL

SELECT
    NULL::int,
    NULL::varchar,
    NULL::int,
    NULL::int,
    NULL::int,
    NULL::int,
    NULL::int,
    NULL::int,
    NULL::timestamp,
    NULL::timestamp,
    NULL::int,
    ts.TagName,
    ts.tag_use_cnt,
    ts.total_score,
    ts.question_cnt,
    ts.top_contributors,
    NULL::int
FROM tag_stats ts
ORDER BY
    rank_position NULLS LAST,
    tag_use_cnt DESC,
    total_score DESC
LIMIT 150;
