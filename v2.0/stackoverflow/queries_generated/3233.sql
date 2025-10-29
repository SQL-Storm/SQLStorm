-- {"query": "3233.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1633} 

/*  Performance‑benchmarking query – combines CTEs, window functions, outer joins,
    correlated subqueries, set operators, complex predicates, string manipulation
    and NULL handling. */

WITH 
-- 1️⃣ Aggregate basic user stats
user_base AS (
    SELECT 
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate                         AS user_since,
        COALESCE(u.Views,0)                    AS total_views,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS net_votes,
        COUNT(b.Id)                            AS badge_count,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),

-- 2️⃣ Recent activity per user (correlated sub‑query for latest post & latest vote)
recent_activity AS (
    SELECT 
        u.Id                                      AS user_id,
        /* latest question or answer posted by the user */
        (SELECT p.Id
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
           AND p.PostTypeId IN (1,2)               -- question or answer
         ORDER BY p.CreationDate DESC
         FETCH FIRST 1 ROW ONLY)                  AS latest_post_id,
        (SELECT p.CreationDate
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
           AND p.PostTypeId IN (1,2)
         ORDER BY p.CreationDate DESC
         FETCH FIRST 1 ROW ONLY)                  AS latest_post_date,
        /* latest vote cast by the user (excluding system votes) */
        (SELECT v.VoteTypeId
         FROM Votes v
         WHERE v.UserId = u.Id
         ORDER BY v.CreationDate DESC
         FETCH FIRST 1 ROW ONLY)                  AS latest_vote_type,
        (SELECT v.CreationDate
         FROM Votes v
         WHERE v.UserId = u.Id
         ORDER BY v.CreationDate DESC
         FETCH FIRST 1 ROW ONLY)                  AS latest_vote_date
    FROM Users u
),

-- 3️⃣ Tag‑level statistics for questions authored by each user
user_tag_stats AS (
    SELECT 
        p.OwnerUserId                                 AS user_id,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM COALESCE(p.Tags,'')), '><')) AS tag,
        COUNT(*)                                      AS q_per_tag,
        AVG(p.Score)                                  AS avg_score_per_tag,
        MAX(p.ViewCount)                              AS max_views_per_tag
    FROM Posts p
    WHERE p.PostTypeId = 1                -- only questions
      AND p.OwnerUserId IS NOT NULL
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),

-- 4️⃣ Rank users by reputation using a window function
ranked_users AS (
    SELECT 
        ub.*,
        RANK() OVER (ORDER BY ub.Reputation DESC)   AS reputation_rank,
        ROW_NUMBER() OVER (PARTITION BY ub.UserId ORDER BY ub.CreationDate DESC) AS rn
    FROM user_base ub
),

-- 5️⃣ Combine everything; also demonstrate a FULL OUTER JOIN with NULL logic
combined AS (
    SELECT 
        ru.user_id,
        ru.DisplayName,
        ru.Reputation,
        ru.reputation_rank,
        ru.total_views,
        ru.net_votes,
        ru.badge_count,
        ru.gold_badges,
        ru.silver_badges,
        ru.bronze_badges,
        ra.latest_post_id,
        ra.latest_post_date,
        ra.latest_vote_type,
        ra.latest_vote_date,
        COALESCE(uts.q_per_tag,0)                      AS questions_per_tag,
        COALESCE(uts.avg_score_per_tag,0)             AS avg_score_per_tag,
        COALESCE(uts.max_views_per_tag,0)             AS max_views_per_tag,
        /* Build a readable tag‑summary string – empty string if no tags */
        CASE 
            WHEN uts.tag IS NULL THEN ''
            ELSE CONCAT('Tag:', uts.tag, 
                        ' (Q:', COALESCE(uts.q_per_tag,0), 
                        ', AvgScore:', ROUND(uts.avg_score_per_tag,2), 
                        ', MaxViews:', COALESCE(uts.max_views_per_tag,0), ')')
        END                                          AS tag_summary
    FROM ranked_users ru
    LEFT JOIN recent_activity ra   ON ra.user_id = ru.user_id
    FULL OUTER JOIN user_tag_stats uts ON uts.user_id = ru.user_id
),

/* 6️⃣ A UNION ALL to pull in "inactive" users (no posts, no votes, no badges)  */
inactive_users AS (
    SELECT 
        u.Id                      AS user_id,
        u.DisplayName,
        u.Reputation,
        NULL                      AS reputation_rank,
        COALESCE(u.Views,0)       AS total_views,
        COALESCE(u.UpVotes,0)-COALESCE(u.DownVotes,0) AS net_votes,
        0                         AS badge_count,
        0                         AS gold_badges,
        0                         AS silver_badges,
        0                         AS bronze_badges,
        NULL                      AS latest_post_id,
        NULL                      AS latest_post_date,
        NULL                      AS latest_vote_type,
        NULL                      AS latest_vote_date,
        0                         AS questions_per_tag,
        0                         AS avg_score_per_tag,
        0                         AS max_views_per_tag,
        ''                        AS tag_summary
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
      AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id)
      AND NOT EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = u.Id)
)

SELECT *
FROM combined
WHERE reputation_rank <= 100                     -- top‑100 users
   OR (tag_summary <> '' AND questions_per_tag >= 5)   -- heavy tag contributors
UNION ALL
SELECT *
FROM inactive_users
WHERE Reputation < 10
ORDER BY reputation_rank NULLS LAST, user_id;
