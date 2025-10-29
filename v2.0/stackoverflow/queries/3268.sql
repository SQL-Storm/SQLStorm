WITH recent_posts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
),
user_badge_agg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        COUNT(*)                                            AS total_badges
    FROM Badges b
    GROUP BY b.UserId
),
user_score_stats AS (
    SELECT
        p.OwnerUserId AS user_id,
        AVG(p.Score)                                     AS avg_post_score,
        MAX(p.Score)                                     AS max_post_score,
        SUM(CASE WHEN p.Score IS NULL THEN 1 ELSE 0 END)  AS null_score_cnt
    FROM Posts p
    WHERE p.PostTypeId = 1      -- only questions
    GROUP BY p.OwnerUserId
),
tag_info AS (
    SELECT
        t.TagName,
        t.Count               AS tag_count,
        CASE
          WHEN t.IsModeratorOnly IS NULL THEN 0
          WHEN t.IsModeratorOnly = TRUE THEN 1
          ELSE 0
        END AS is_mod_only
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
user_recent_counts AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS recent_post_cnt
    FROM recent_posts
    WHERE rn = 1
    GROUP BY OwnerUserId
)
SELECT
    u.Id                                      AS user_id,
    u.DisplayName,
    u.Reputation,
    COALESCE(uba.gold_badges, 0)              AS gold_badges,
    COALESCE(uba.silver_badges, 0)            AS silver_badges,
    COALESCE(uba.bronze_badges, 0)            AS bronze_badges,
    COALESCE(uss.avg_post_score, 0)           AS avg_post_score,
    uss.max_post_score,
    COALESCE(urc.recent_post_cnt, 0)           AS recent_post_cnt,
    CASE
        WHEN u.Reputation > 20000 THEN 'Elite'
        WHEN u.Reputation BETWEEN 10000 AND 20000 THEN 'Pro'
        ELSE 'Member'
    END                                        AS reputation_tier,
    lt.popular_tags,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS reputation_rank,
    (SELECT COUNT(*)
       FROM Posts p3
      WHERE p3.OwnerUserId = u.Id
        AND p3.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '7' DAY) AS weekly_post_cnt,
    (SELECT COUNT(*)
       FROM Votes v
      WHERE v.UserId = u.Id
        AND v.VoteTypeId = 2)                AS upvote_given_cnt
FROM Users u
LEFT JOIN user_badge_agg uba      ON uba.UserId = u.Id
LEFT JOIN user_score_stats uss    ON uss.user_id = u.Id
LEFT JOIN user_recent_counts urc  ON urc.OwnerUserId = u.Id
LEFT JOIN LATERAL (
    SELECT STRING_AGG(DISTINCT ti.TagName, ', ') AS popular_tags
    FROM (
        SELECT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '><'))) AS tag
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.Tags IS NOT NULL
        LIMIT 100
    ) pt
    JOIN tag_info ti ON ti.TagName = pt.tag
    WHERE ti.is_mod_only = 0
) lt ON TRUE
GROUP BY
    u.Id, u.DisplayName, u.Reputation,
    uba.gold_badges, uba.silver_badges, uba.bronze_badges,
    uss.avg_post_score, uss.max_post_score,
    urc.recent_post_cnt, lt.popular_tags
HAVING COUNT(*) > 0

UNION ALL

SELECT
    NULL                                      AS user_id,
    'SUMMARY'                                 AS displayname,
    NULL                                      AS reputation,
    SUM(COALESCE(uba.gold_badges,0))           AS gold_badges,
    SUM(COALESCE(uba.silver_badges,0))         AS silver_badges,
    SUM(COALESCE(uba.bronze_badges,0))         AS bronze_badges,
    AVG(COALESCE(uss.avg_post_score,0))       AS avg_post_score,
    MAX(uss.max_post_score)                   AS max_post_score,
    SUM(COALESCE(urc.recent_post_cnt,0))      AS recent_post_cnt,
    NULL                                      AS reputation_tier,
    NULL                                      AS popular_tags,
    NULL                                      AS reputation_rank,
    NULL                                      AS weekly_post_cnt,
    NULL                                      AS upvote_given_cnt
FROM Users u
LEFT JOIN user_badge_agg uba   ON uba.UserId = u.Id
LEFT JOIN user_score_stats uss ON uss.user_id = u.Id
LEFT JOIN user_recent_counts urc ON urc.OwnerUserId = u.Id;