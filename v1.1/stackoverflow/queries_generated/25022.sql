-- {"query": "25022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1723} 

/*  Complex performance‑benchmark query for the StackOverflow schema  */
WITH 
/* 1️⃣  Aggregate post data per user (including users without posts) */
user_post_agg AS (
    SELECT
        u.Id                                   AS user_id,
        COALESCE(u.DisplayName, 'anonymous')   AS display_name,
        COUNT(p.Id)                             AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers,
        SUM(COALESCE(p.Score,0))                AS sum_score,
        MAX(p.CreationDate)                    AS last_post_date,
        STRING_AGG(DISTINCT p.Tags, ';') FILTER (WHERE p.Tags IS NOT NULL) AS all_tags
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

/* 2️⃣  Compute badge statistics per user */
user_badge_stats AS (
    SELECT
        b.UserId                               AS user_id,
        COUNT(*)                               AS badge_count,
        COUNT(*) FILTER (WHERE b.Class = 1)    AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2)    AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3)    AS bronze_badges,
        MAX(b.Date)                            AS latest_badge_date
    FROM Badges b
    GROUP BY b.UserId
),

/* 3️⃣  Recent voting activity (last 30 days) */
recent_votes AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        COUNT(*)                               AS vote_cnt,
        MAX(v.CreationDate)                    AS last_vote
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId, v.VoteTypeId
),

/* 4️⃣  Tag popularity derived from Posts.Tags (flattened) */
tag_usage AS (
    SELECT
        TRIM(t)                                 AS tag,
        COUNT(*)                                AS usage_cnt
    FROM (
        SELECT UNNEST(STRING_TO_ARRAY(
                 REPLACE(REPLACE(Posts.Tags, '<', ''), '>', ''), 
                 ' ')) AS t
        FROM Posts
        WHERE Posts.Tags IS NOT NULL
    ) flat
    GROUP BY TRIM(t)
),

/* 5️⃣  Top‑5 tags per user based on usage in their questions */
user_top_tags AS (
    SELECT
        u.Id                                    AS user_id,
        tag,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY cnt DESC) AS rn
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(
                 REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), 
                 ' ')) AS tag
    ) t
    JOIN (
        SELECT tag, COUNT(*) AS cnt
        FROM (
            SELECT UNNEST(STRING_TO_ARRAY(
                     REPLACE(REPLACE(p2.Tags, '<', ''), '>', ''), 
                     ' ')) AS tag
            FROM Posts p2
            WHERE p2.PostTypeId = 1
        ) sub
        GROUP BY tag
    ) tu ON tu.tag = t.tag
    GROUP BY u.Id, tag, cnt
),

/* 6️⃣  Combine aggregates, badge stats and recent vote totals */
user_combined AS (
    SELECT
        upa.user_id,
        upa.display_name,
        upa.total_posts,
        upa.questions,
        upa.answers,
        upa.sum_score,
        upa.last_post_date,
        upa.all_tags,
        COALESCE(ubs.badge_count,0)           AS badge_count,
        COALESCE(ubs.gold_badges,0)           AS gold_badges,
        COALESCE(ubs.silver_badges,0)         AS silver_badges,
        COALESCE(ubs.bronze_badges,0)         AS bronze_badges,
        ubs.latest_badge_date,
        COALESCE(rv.vote_cnt,0)               AS recent_votes,
        rv.last_vote
    FROM user_post_agg upa
    LEFT JOIN user_badge_stats ubs   ON ubs.user_id = upa.user_id
    LEFT JOIN (
        SELECT 
            p.OwnerUserId               AS owner_id,
            SUM(rv.vote_cnt)            AS vote_cnt,
            MAX(rv.last_vote)           AS last_vote
        FROM Posts p
        LEFT JOIN recent_votes rv    ON rv.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) rv ON rv.owner_id = upa.user_id
)

/* 7️⃣  Final result set with ranking and a UNION ALL for a lightweight baseline */
SELECT
    uc.user_id,
    uc.display_name,
    uc.total_posts,
    uc.questions,
    uc.answers,
    uc.sum_score,
    uc.badge_count,
    uc.gold_badges,
    uc.silver_badges,
    uc.bronze_badges,
    uc.recent_votes,
    CASE 
        WHEN uc.sum_score IS NULL THEN NULL
        WHEN uc.sum_score >= 10000 THEN 'Elite'
        WHEN uc.sum_score >= 5000  THEN 'Pro'
        ELSE 'Regular'
    END                                           AS tier,
    ROW_NUMBER() OVER (ORDER BY uc.sum_score DESC NULLS LAST) AS rank_by_score,
    STRING_AGG(tt.tag, ', ') FILTER (WHERE tt.rn <= 5)             AS top_5_tags
FROM user_combined uc
LEFT JOIN user_top_tags tt ON tt.user_id = uc.user_id
GROUP BY 
    uc.user_id, uc.display_name, uc.total_posts, uc.questions,
    uc.answers, uc.sum_score, uc.badge_count, uc.gold_badges,
    uc.silver_badges, uc.bronze_badges, uc.recent_votes, uc.tier,
    uc.rank_by_score
HAVING COUNT(*) > 0

UNION ALL

/* 8️⃣  Baseline: only users with at least one gold badge, no window functions */
SELECT
    u.Id                                   AS user_id,
    u.DisplayName                          AS display_name,
    0                                      AS total_posts,
    0                                      AS questions,
    0                                      AS answers,
    0                                      AS sum_score,
    COUNT(b.Id)                            AS badge_count,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
    0                                      AS silver_badges,
    0                                      AS bronze_badges,
    0                                      AS recent_votes,
    NULL                                   AS tier
FROM Users u
JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
GROUP BY u.Id, u.DisplayName
ORDER BY gold_badges DESC, badge_count DESC;
