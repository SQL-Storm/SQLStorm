-- {"query": "3355.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2570} 

WITH
-- split tags of questions into one row per tag
tag_expansion AS (
    SELECT
        p.Id               AS question_id,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '><')) ) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1            -- only questions
      AND p.Tags IS NOT NULL
),

-- aggregate answer statistics per user
user_answer_stats AS (
    SELECT
        a.OwnerUserId                                           AS user_id,
        COUNT(*)                                                AS total_answers,
        COUNT(*) FILTER (WHERE a.Score > 0)                     AS positive_answers,
        COUNT(*) FILTER (WHERE a.Score <= 0)                    AS non_positive_answers,
        ROUND(AVG(a.Score)::numeric,2)                          AS avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score)    AS median_score
    FROM Posts a
    WHERE a.PostTypeId = 2               -- only answers
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
),

-- badge aggregates per user
user_badge_stats AS (
    SELECT
        b.UserId                                      AS user_id,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)  AS gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)  AS silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)  AS bronze,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS tag_based
    FROM Badges b
    GROUP BY b.UserId
),

-- recent vote activity per user (only up‑votes for speed)
user_vote_stats AS (
    SELECT
        v.UserId                              AS user_id,
        COUNT(*)                              AS up_votes_cast,
        MAX(v.CreationDate)                   AS last_upvote
    FROM Votes v
    WHERE v.VoteTypeId = 2                     -- up‑vote
    GROUP BY v.UserId
),

-- rank users by reputation and merge all stats
ranked_users AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ua.total_answers,0)          AS total_answers,
        COALESCE(ua.positive_answers,0)       AS positive_answers,
        COALESCE(ua.non_positive_answers,0)   AS non_positive_answers,
        COALESCE(ua.avg_score,0)              AS avg_score,
        COALESCE(ua.median_score,0)           AS median_score,
        COALESCE(ub.gold,0)                   AS gold_badges,
        COALESCE(ub.silver,0)                 AS silver_badges,
        COALESCE(ub.bronze,0)                 AS bronze_badges,
        COALESCE(ub.tag_based,0)              AS tag_badges,
        COALESCE(uv.up_votes_cast,0)          AS up_votes_cast,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rep_rank
    FROM Users u
    LEFT JOIN user_answer_stats ua ON ua.user_id = u.Id
    LEFT JOIN user_badge_stats   ub ON ub.user_id = u.Id
    LEFT JOIN user_vote_stats    uv ON uv.user_id = u.Id
    WHERE u.Reputation > 5000
),

-- compute per‑tag activity for the top‑ranked users
user_tag_activity AS (
    SELECT
        ru.Id                                 AS user_id,
        COUNT(DISTINCT te.tag)                AS distinct_tags_answered,
        STRING_AGG(DISTINCT te.tag, ',')      FILTER (WHERE te.tag IS NOT NULL) AS tags_list
    FROM ranked_users ru
    JOIN Posts a ON a.OwnerUserId = ru.Id AND a.PostTypeId = 2
    JOIN tag_expansion te ON te.question_id = a.ParentId
    GROUP BY ru.Id
),

-- final result set: top 30 users with rich info
top_users AS (
    SELECT
        ru.rep_rank,
        ru.DisplayName,
        ru.Reputation,
        ru.total_answers,
        ru.positive_answers,
        ru.non_positive_answers,
        ru.avg_score,
        ru.median_score,
        ru.gold_badges,
        ru.silver_badges,
        ru.bronze_badges,
        ru.tag_badges,
        ru.up_votes_cast,
        COALESCE(uta.distinct_tags_answered,0)           AS distinct_tags_answered,
        COALESCE(uta.tags_list,'')                       AS tags_list,
        CASE
            WHEN ru.gold_badges >= 5 THEN 'Elite'
            WHEN ru.silver_badges >= 10 THEN 'Veteran'
            ELSE 'Contributor'
        END                                              AS tier,
        CONCAT('https://stackoverflow.com/users/', ru.Id) AS profile_url
    FROM ranked_users ru
    LEFT JOIN user_tag_activity uta ON uta.user_id = ru.Id
    WHERE ru.rep_rank <= 30
)

-- output the data and a summary row using set operators
SELECT *
FROM top_users

UNION ALL

SELECT
    NULL AS rep_rank,
    '---' AS DisplayName,
    NULL AS Reputation,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL AS distinct_tags_answered,
    NULL AS tags_list,
    'Summary' AS tier,
    NULL AS profile_url
FROM (SELECT 1) s

UNION ALL

SELECT
    NULL,
    'TOTALS',
    (SELECT COUNT(*) FROM Users),
    (SELECT SUM(total_answers)    FROM ranked_users),
    (SELECT SUM(positive_answers) FROM ranked_users),
    (SELECT SUM(non_positive_answers) FROM ranked_users),
    (SELECT ROUND(AVG(avg_score)::numeric,2) FROM ranked_users),
    (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY median_score) FROM ranked_users),
    (SELECT SUM(gold_badges)   FROM ranked_users),
    (SELECT SUM(silver_badges) FROM ranked_users),
    (SELECT SUM(bronze_badges) FROM ranked_users),
    (SELECT SUM(tag_badges)    FROM ranked_users),
    (SELECT SUM(up_votes_cast) FROM ranked_users),
    NULL,
    NULL,
    NULL,
    NULL
ORDER BY rep_rank NULLS LAST;
