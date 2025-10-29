-- {"query": "3577.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2208} 

WITH recent_posts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

badge_agg AS (
    SELECT 
        b.UserId,
        COUNT(*)                         AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),

post_stats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*)                         AS total_posts,
        SUM(p.Score)                     AS sum_score,
        AVG(p.Score)                     AS avg_score,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS question_cnt,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answer_cnt
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

latest_activity AS (
    SELECT 
        u.Id                               AS user_id,
        MAX(p.CreationDate)                AS last_post_date
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),

union_activity AS (
    SELECT u.Id        AS user_id,
           u.DisplayName,
           'Question'   AS activity_type,
           p.CreationDate
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1

    UNION ALL

    SELECT u.Id,
           u.DisplayName,
           'Answer'     AS activity_type,
           p.CreationDate
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
),

duplicate_link AS (
    SELECT 
        u.Id                                     AS user_id,
        CASE 
            WHEN EXISTS (
                SELECT 1
                FROM PostLinks pl
                WHERE pl.PostId = (
                    SELECT p.Id
                    FROM Posts p
                    WHERE p.OwnerUserId = u.Id
                    ORDER BY p.CreationDate DESC
                    LIMIT 1
                )
                AND pl.LinkTypeId = 3   -- Duplicate link
            ) THEN 1 ELSE 0
        END                                     AS has_duplicate_link
    FROM Users u
)

SELECT 
    u.Id                                          AS user_id,
    COALESCE(u.DisplayName, 'Anonymous')          AS display_name,
    u.Reputation,
    COALESCE(b.total_badges, 0)                   AS total_badges,
    COALESCE(b.gold_badges, 0)                    AS gold_badges,
    COALESCE(b.silver_badges, 0)                  AS silver_badges,
    COALESCE(b.bronze_badges, 0)                  AS bronze_badges,
    COALESCE(ps.total_posts, 0)                   AS total_posts,
    COALESCE(ps.sum_score, 0)                     AS total_score,
    ROUND(COALESCE(ps.avg_score, 0), 2)           AS avg_score,
    COALESCE(ps.question_cnt, 0)                  AS question_count,
    COALESCE(ps.answer_cnt, 0)                    AS answer_count,
    COALESCE(la.last_post_date, u.CreationDate)   AS last_activity,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC,
                                 COALESCE(ps.total_posts,0) DESC) AS reputation_rank,
    CASE 
        WHEN EXISTS (
            SELECT 1
            FROM Posts p
            WHERE p.OwnerUserId = u.Id
              AND p.Tags LIKE '%<sql>%'
        ) THEN 1 ELSE 0
    END                                           AS has_sql_tag,
    d.has_duplicate_link
FROM Users u
LEFT JOIN badge_agg b     ON b.UserId = u.Id
LEFT JOIN post_stats ps   ON ps.OwnerUserId = u.Id
LEFT JOIN latest_activity la ON la.user_id = u.Id
LEFT JOIN duplicate_link d    ON d.user_id = u.Id
WHERE u.Reputation > 1000
  AND (u.Location IS NOT NULL OR u.WebsiteUrl ILIKE '%.com%')
ORDER BY reputation_rank
LIMIT 100;
