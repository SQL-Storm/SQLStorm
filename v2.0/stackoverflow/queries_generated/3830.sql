-- {"query": "3830.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1832} 

/*  Benchmark query: complex user‑centric analytics */
WITH RECURSIVE user_activity AS (
    SELECT
        u.Id                     AS user_id,
        u.DisplayName            AS user_name,
        u.Reputation             AS reputation,
        u.CreationDate           AS user_created,
        u.LastAccessDate         AS last_access,
        COALESCE(u.Location, '') AS location,
        /* total posts */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id)                                      AS total_posts,
        /* total questions */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)                AS total_questions,
        /* total answers */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2)                AS total_answers,
        /* recent activity (last 30 days) */
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
           AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '30 days'))                         AS recent_posts,
        /* avg score of all posts */
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id)                                 AS avg_score,
        /* flag if user has never received a badge */
        CASE WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id) THEN 0 ELSE 1 END           AS has_no_badge
    FROM Users u
    WHERE u.Id IS NOT NULL
),
top_posts AS (
    SELECT
        p.OwnerUserId            AS user_id,
        p.Id                     AS post_id,
        p.Title                  AS title,
        p.Score                  AS score,
        p.CreationDate           AS created,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)          -- only questions & answers
),
user_top_posts AS (
    SELECT
        tp.user_id,
        STRING_AGG(
            CONCAT('(', tp.post_id, ') ', COALESCE(tp.title, '[no title]'), ' [', tp.score, ']'), 
            ' | '
            ORDER BY tp.rn
        ) AS top_posts_summary
    FROM top_posts tp
    WHERE tp.rn <= 3                       -- top 3 posts per user
    GROUP BY tp.user_id
),
tag_usage AS (
    SELECT
        p.OwnerUserId            AS user_id,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag,
        COUNT(*)                 AS tag_cnt
    FROM Posts p
    WHERE p.Tags IS NOT NULL
      AND p.PostTypeId = 1               -- only questions
    GROUP BY p.OwnerUserId, tag
),
user_top_tags AS (
    SELECT
        tu.user_id,
        STRING_AGG(
            CONCAT(tu.tag, '(', tu.tag_cnt, ')'),
            ', '
            ORDER BY tu.tag_cnt DESC, tu.tag
        ) AS tags_summary
    FROM (
        SELECT
            user_id,
            tag,
            tag_cnt,
            ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_cnt DESC, tag) AS rn
        FROM tag_usage
    ) tu
    WHERE tu.rn <= 5                      -- top 5 tags per user
    GROUP BY tu.user_id
),
vote_summary AS (
    SELECT
        p.OwnerUserId                       AS user_id,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)   AS upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)   AS downvotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END)   AS favorites
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
/* Combine all metrics using FULL OUTER JOIN to stress the optimizer */
combined_metrics AS (
    SELECT
        ua.user_id,
        ua.user_name,
        ua.reputation,
        ua.location,
        ua.total_posts,
        ua.total_questions,
        ua.total_answers,
        ua.recent_posts,
        ua.avg_score,
        ua.has_no_badge,
        COALESCE(utp.top_posts_summary, '')               AS top_posts,
        COALESCE(utg.tags_summary, '')                    AS top_tags,
        COALESCE(vs.upvotes,0)                            AS total_upvotes,
        COALESCE(vs.downvotes,0)                          AS total_downvotes,
        COALESCE(vs.favorites,0)                          AS total_favorites,
        /* derived metric: engagement score */
        (COALESCE(vs.upvotes,0) - COALESCE(vs.downvotes,0) + 
         COALESCE(vs.favorites,0) * 2 + 
         COALESCE(ua.total_questions,0) * 3 + 
         COALESCE(ua.total_answers,0) * 4)               AS engagement_score
    FROM user_activity ua
    FULL OUTER JOIN user_top_posts utp ON utp.user_id = ua.user_id
    FULL OUTER JOIN user_top_tags utg   ON utg.user_id = ua.user_id
    FULL OUTER JOIN vote_summary vs    ON vs.user_id = ua.user_id
)
SELECT
    cm.user_id,
    cm.user_name,
    cm.reputation,
    cm.location,
    cm.total_posts,
    cm.total_questions,
    cm.total_answers,
    cm.recent_posts,
    ROUND(cm.avg_score::numeric,2)                AS avg_score,
    cm.has_no_badge,
    cm.top_posts,
    cm.top_tags,
    cm.total_upvotes,
    cm.total_downvotes,
    cm.total_favorites,
    cm.engagement_score
FROM combined_metrics cm
WHERE cm.engagement_score > 0
ORDER BY cm.engagement_score DESC
LIMIT 100
UNION ALL
SELECT
    NULL AS user_id,
    'TOTAL' AS user_name,
    SUM(cm.reputation)               AS reputation,
    NULL AS location,
    SUM(cm.total_posts)              AS total_posts,
    SUM(cm.total_questions)          AS total_questions,
    SUM(cm.total_answers)            AS total_answers,
    SUM(cm.recent_posts)             AS recent_posts,
    ROUND(AVG(cm.avg_score)::numeric,2) AS avg_score,
    NULL AS has_no_badge,
    NULL AS top_posts,
    NULL AS top_tags,
    SUM(cm.total_upvotes)            AS total_upvotes,
    SUM(cm.total_downvotes)          AS total_downvotes,
    SUM(cm.total_favorites)          AS total_favorites,
    SUM(cm.engagement_score)         AS engagement_score
FROM combined_metrics cm
HAVING COUNT(*) > 0;
