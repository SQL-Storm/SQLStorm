-- {"query": "3642.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2436} 

/*  Benchmark‑heavy query on the StackOverflow schema  */
WITH
/* --------------------------------------------------------------
   1️⃣  Aggregate badge counts per user (including NULL handling) */
badge_counts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze
    FROM Badges b
    GROUP BY b.UserId
),

/* --------------------------------------------------------------
   2️⃣  Core user statistics with correlated sub‑queries */
user_stats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.gold,0)   AS gold_badges,
        COALESCE(bc.silver,0) AS silver_badges,
        COALESCE(bc.bronze,0) AS bronze_badges,

        /* total questions asked */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS q_cnt,

        /* total answers posted */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS a_cnt,

        /* average question score (NULL → 0) */
        COALESCE(
            (SELECT AVG(p.Score)::numeric
             FROM Posts p
             WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1),
            0) AS avg_q_score,

        /* most recent activity on any of the user’s posts */
        (SELECT MAX(p.LastActivityDate)
         FROM Posts p
         WHERE p.OwnerUserId = u.Id) AS last_post_activity
    FROM Users u
    LEFT JOIN badge_counts bc ON bc.UserId = u.Id
),

/* --------------------------------------------------------------
   3️⃣  Rank the “elite” users */
ranked_users AS (
    SELECT
        us.*,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC,
                                 us.gold_badges DESC,
                                 us.avg_q_score DESC) AS rn
    FROM user_stats us
    WHERE us.Reputation >= 10000
),

/* --------------------------------------------------------------
   4️⃣  De‑normalize tags per question for fast pattern matching */
question_tags AS (
    SELECT
        p.Id               AS q_id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        UNNEST(string_to_array(substr(p.Tags,2,length(p.Tags)-2), '><')) AS tag,
        /* vote delta per question */
        COALESCE(v.up,0) - COALESCE(v.down,0) AS vote_delta,
        CASE
            WHEN p.ClosedDate IS NOT NULL          THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL  THEN 'CommunityOwned'
            ELSE 'Open'
        END AS status
    FROM Posts p
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down
        FROM Votes v
        GROUP BY v.PostId
    ) v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1               -- only questions
      AND p.Tags IS NOT NULL
      AND (p.Tags LIKE '%<sql>%'
           OR p.Tags LIKE '%<performance>%')
),

/* --------------------------------------------------------------
   5️⃣  Recent comment activity per user */
recent_comments AS (
    SELECT
        c.UserId,
        MAX(c.CreationDate) AS last_comment_dt
    FROM Comments c
    GROUP BY c.UserId
),

/* --------------------------------------------------------------
   6️⃣  Combine everything for the final report */
final_report AS (
    SELECT
        ru.Id,
        ru.DisplayName,
        ru.Reputation,
        ru.gold_badges,
        ru.silver_badges,
        ru.bronze_badges,
        ru.q_cnt,
        ru.a_cnt,
        ROUND(ru.avg_q_score,2)               AS avg_q_score,
        ru.last_post_activity,
        rc.last_comment_dt,
        /* collect distinct tags the user ever touched */
        STRING_AGG(DISTINCT qt.tag, ',') FILTER (WHERE qt.tag IS NOT NULL) AS tags_used,
        COUNT(DISTINCT qt.q_id)               AS tagged_q_cnt,
        SUM(qt.vote_delta)                    AS total_vote_delta,
        MAX(CASE WHEN qt.status = 'Closed' THEN 1 ELSE 0 END) AS has_closed_q
    FROM ranked_users ru
    LEFT JOIN recent_comments rc ON rc.UserId = ru.Id
    LEFT JOIN question_tags qt   ON qt.OwnerUserId = ru.Id
    GROUP BY
        ru.Id, ru.DisplayName, ru.Reputation,
        ru.gold_badges, ru.silver_badges, ru.bronze_badges,
        ru.q_cnt, ru.a_cnt, ru.avg_q_score,
        ru.last_post_activity, rc.last_comment_dt
    HAVING COUNT(DISTINCT qt.q_id) > 5          -- filter noisy users
)

/* --------------------------------------------------------------
   7️⃣  Final output with a set‑operator twist (UNION ALL) */
SELECT *
FROM final_report
ORDER BY rn
LIMIT 20

UNION ALL

/* dummy branch to force a set‑operator plan */
SELECT
    NULL::int     AS Id,
    NULL::varchar AS DisplayName,
    NULL::int     AS Reputation,
    NULL::int     AS gold_badges,
    NULL::int     AS silver_badges,
    NULL::int     AS bronze_badges,
    NULL::int     AS q_cnt,
    NULL::int     AS a_cnt,
    NULL::numeric AS avg_q_score,
    NULL::timestamp AS last_post_activity,
    NULL::timestamp AS last_comment_dt,
    NULL::varchar AS tags_used,
    NULL::int     AS tagged_q_cnt,
    NULL::int     AS total_vote_delta,
    NULL::int     AS has_closed_q
WHERE FALSE;   -- guarantees zero rows from this branch
