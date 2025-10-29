-- {"query": "3286.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2472} 

WITH
    -- Count badges per user, split by class
    user_badge_counts AS (
        SELECT
            u.Id                      AS user_id,
            u.DisplayName,
            u.Reputation,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    -- Aggregate post statistics per user
    user_post_stats AS (
        SELECT
            p.OwnerUserId                     AS user_id,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions_asked,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers_given,
            SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS questions_with_accepted,
            SUM(p.Score)                     AS total_score,
            MAX(p.CreationDate)              AS last_post_dt
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- Latest vote (up/down) per post using a window function
    latest_vote_per_post AS (
        SELECT
            v.PostId,
            v.VoteTypeId,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
        FROM Votes v
        WHERE v.VoteTypeId IN (2,3)   -- up‑vote / down‑vote
    ),
    post_latest_vote AS (
        SELECT
            lv.PostId,
            lv.VoteTypeId,
            lv.CreationDate AS latest_vote_dt
        FROM latest_vote_per_post lv
        WHERE lv.rn = 1
    ),

    -- Tag usage across all posts (string search on the <tag> format)
    tag_usage AS (
        SELECT
            t.TagName,
            COUNT(p.Id)                         AS tag_post_cnt,
            SUM(p.Score)                        AS tag_score_sum,
            COUNT(DISTINCT p.OwnerUserId)       AS distinct_authors
        FROM Tags t
        JOIN Posts p
            ON p.Tags IS NOT NULL
           AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
        GROUP BY t.TagName
    ),

    -- Top tag per user (first tag by count)
    top_tag_per_user AS (
        SELECT
            up.OwnerUserId                      AS user_id,
            tg.TagName,
            ROW_NUMBER() OVER (PARTITION BY up.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
        FROM Posts up
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(substring(up.Tags, 2, length(up.Tags)-2), '><')) AS tag
        ) AS tags(tag)
        JOIN Tags tg ON tg.TagName = tags.tag
        GROUP BY up.OwnerUserId, tg.TagName
    ),

    -- Rank users by reputation + badge weight, compute acceptance rate
    ranked_users AS (
        SELECT
            ubc.user_id,
            ubc.DisplayName,
            ubc.Reputation,
            ubc.gold_badges,
            ubc.silver_badges,
            ubc.bronze_badges,
            COALESCE(ups.questions_asked,0)          AS questions_asked,
            COALESCE(ups.answers_given,0)            AS answers_given,
            COALESCE(ups.questions_with_accepted,0) AS questions_with_accepted,
            COALESCE(ups.total_score,0)              AS total_score,
            ups.last_post_dt,
            CASE
                WHEN ups.questions_asked = 0 THEN NULL
                ELSE ROUND(ups.questions_with_accepted::numeric / ups.questions_asked, 3)
            END                                      AS acceptance_rate,
            ROW_NUMBER() OVER (ORDER BY ubc.Reputation DESC,
                                         ubc.gold_badges DESC,
                                         ubc.silver_badges DESC) AS rank_by_rep
        FROM user_badge_counts ubc
        LEFT JOIN user_post_stats ups ON ups.user_id = ubc.user_id
    )

SELECT
    ru.rank_by_rep,
    ru.DisplayName,
    ru.Reputation,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    ru.questions_asked,
    ru.answers_given,
    ru.acceptance_rate,
    ru.total_score,
    ru.last_post_dt,
    COALESCE(tpu.TagName, 'N/A')                AS top_tag,
    COALESCE(plv.latest_vote_dt,
             TIMESTAMP '1970-01-01')           AS last_vote_dt
FROM ranked_users ru
LEFT JOIN top_tag_per_user tpu
       ON tpu.user_id = ru.user_id AND tpu.rn = 1
LEFT JOIN Posts lp
       ON lp.OwnerUserId = ru.user_id AND lp.CreationDate = ru.last_post_dt
LEFT JOIN post_latest_vote plv
       ON plv.PostId = lp.Id
WHERE ru.rank_by_rep <= 100
ORDER BY ru.rank_by_rep

UNION ALL

SELECT
    NULL, '---', NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL
LIMIT 101;
