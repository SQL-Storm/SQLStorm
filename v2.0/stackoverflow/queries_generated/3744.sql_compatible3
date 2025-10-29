WITH 
user_activity AS (
    SELECT 
        u.Id                                         AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)  AS question_cnt,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)  AS answer_cnt,
        COALESCE(SUM(p.Score),0)                     AS total_score,
        MAX(p.CreationDate)                          AS last_post_dt
    FROM Users u
    LEFT JOIN Posts p 
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_summary AS (
    SELECT 
        b.UserId                                    AS user_id,
        COUNT(*)                                    AS badge_total,
        COUNT(*) FILTER (WHERE b.Class = 1)         AS gold_cnt,
        COUNT(*) FILTER (WHERE b.Class = 2)         AS silver_cnt,
        COUNT(*) FILTER (WHERE b.Class = 3)         AS bronze_cnt
    FROM Badges b
    GROUP BY b.UserId
),
recent_votes AS (
    SELECT 
        v.UserId                                    AS user_id,
        COUNT(*)                                    AS vote_cnt,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)  AS up_votes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)  AS down_votes,
        MAX(v.CreationDate)                         AS last_vote_dt
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (DATE '2024-10-01' - INTERVAL '30 days')
    GROUP BY v.UserId
),
top_tags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC)  AS tag_rank
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
)

SELECT
    ua.user_id,
    ua.DisplayName,
    ua.Reputation,
    ua.question_cnt,
    ua.answer_cnt,
    ua.total_score,
    COALESCE(bs.badge_total,0)                     AS badge_total,
    COALESCE(bs.gold_cnt,0)                        AS gold_badges,
    COALESCE(bs.silver_cnt,0)                      AS silver_badges,
    COALESCE(bs.bronze_cnt,0)                      AS bronze_badges,
    COALESCE(rv.vote_cnt,0)                        AS recent_vote_cnt,
    COALESCE(rv.up_votes,0)                        AS recent_up_votes,
    COALESCE(rv.down_votes,0)                      AS recent_down_votes,
    ua.last_post_dt,
    rv.last_vote_dt,
    CASE
        WHEN ua.Reputation >= 20000 THEN 'Elite'
        WHEN ua.Reputation >= 10000 THEN 'Pro'
        WHEN ua.Reputation >= 5000  THEN 'Advanced'
        ELSE 'Regular'
    END                                            AS reputation_tier,
    STRING_AGG(DISTINCT t.TagName, ', ') 
        FILTER (WHERE t.TagName IS NOT NULL)       AS top_user_tags
FROM user_activity ua
LEFT JOIN badge_summary bs      ON bs.user_id = ua.user_id
LEFT JOIN recent_votes rv      ON rv.user_id = ua.user_id
LEFT JOIN LATERAL (
        SELECT 
            TRIM(BOTH '<>' FROM UNNEST(STRING_TO_ARRAY(p.Tags, '><'))) AS raw_tag
        FROM Posts p
        WHERE p.OwnerUserId = ua.user_id
          AND p.PostTypeId = 1
        ORDER BY p.Score DESC
        LIMIT 5
) qtags ON TRUE
LEFT JOIN LATERAL (
        SELECT 
            t.TagName
        FROM Tags t
        WHERE t.TagName = qtags.raw_tag
    ) t ON TRUE
WHERE ua.Reputation IS NOT NULL
  AND (ua.question_cnt + ua.answer_cnt) > 0
  AND (ua.last_post_dt IS NULL OR ua.last_post_dt > (DATE '2024-10-01' - INTERVAL '5 years'))
GROUP BY 
    ua.user_id, ua.DisplayName, ua.Reputation,
    ua.question_cnt, ua.answer_cnt, ua.total_score,
    bs.badge_total, bs.gold_cnt, bs.silver_cnt, bs.bronze_cnt,
    rv.vote_cnt, rv.up_votes, rv.down_votes,
    ua.last_post_dt, rv.last_vote_dt,
    CASE
        WHEN ua.Reputation >= 20000 THEN 'Elite'
        WHEN ua.Reputation >= 10000 THEN 'Pro'
        WHEN ua.Reputation >= 5000  THEN 'Advanced'
        ELSE 'Regular'
    END

UNION ALL

SELECT 
    NULL AS user_id,
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS question_cnt,
    NULL AS answer_cnt,
    NULL AS total_score,
    NULL AS badge_total,
    NULL AS gold_badges,
    NULL AS silver_badges,
    NULL AS bronze_badges,
    NULL AS recent_vote_cnt,
    NULL AS recent_up_votes,
    NULL AS recent_down_votes,
    NULL AS last_post_dt,
    NULL AS last_vote_dt,
    NULL AS reputation_tier,
    NULL AS top_user_tags
WHERE NOT EXISTS (SELECT 1 FROM user_activity WHERE Reputation >= 0);