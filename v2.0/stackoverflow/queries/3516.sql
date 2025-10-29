-- {"query": "3516.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2401} 
WITH user_stats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                                            AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)      AS questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)      AS answers,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)       AS avg_score,
        MAX(p.CreationDate)                                    AS last_post_date,
        MAX(v.CreationDate)                                    AS last_vote_date
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

badge_counts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1)                AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2)                AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3)                AS bronze_badges,
        STRING_AGG(DISTINCT b.Name, ', ')                  AS badge_names
    FROM Badges b
    GROUP BY b.UserId
),

top_tags AS (
    SELECT
        pu.UserId,
        STRING_AGG(t.TagName, ', ' ORDER BY pu.tag_usage DESC) AS top_5_tags
    FROM (
        SELECT
            p.OwnerUserId                                     AS UserId,
            regexp_replace(trim(both '<>' from unnest(string_to_array(p.Tags, '><'))), '\s+', '') AS TagName,
            COUNT(*)                                          AS tag_usage
        FROM Posts p
        WHERE p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, TagName
    ) pu
    JOIN Tags t ON t.TagName = pu.TagName
    GROUP BY pu.UserId
),

recent_activity AS (
    SELECT
        u.Id,
        MAX(p.LastActivityDate)                            AS recent_post_activity,
        MAX(c.CreationDate)                                 AS recent_comment_activity
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id
)

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(us.total_posts,0)                     AS total_posts,
    COALESCE(us.questions,0)                       AS questions,
    COALESCE(us.answers,0)                         AS answers,
    ROUND(COALESCE(us.avg_score,0),2)              AS avg_score,
    us.last_post_date,
    us.last_vote_date,
    bc.gold_badges,
    bc.silver_badges,
    bc.bronze_badges,
    bc.badge_names,
    tt.top_5_tags,
    ra.recent_post_activity,
    ra.recent_comment_activity,
    RANK() OVER (ORDER BY u.Reputation DESC)       AS reputation_rank,
    CASE
        WHEN u.Location IS NULL OR trim(u.Location) = '' THEN 'Unknown'
        ELSE u.Location
    END                                           AS user_location,
    (SELECT COUNT(*)
     FROM Votes v
     WHERE v.UserId = u.Id
       AND v.VoteTypeId = 2
       AND v.CreationDate > cast('2024-10-01' as date) - INTERVAL '30 day') AS upvotes_last_30d
FROM Users u
LEFT JOIN user_stats     us ON us.Id = u.Id
LEFT JOIN badge_counts   bc ON bc.UserId = u.Id
LEFT JOIN top_tags       tt ON tt.UserId = u.Id
LEFT JOIN recent_activity ra ON ra.Id = u.Id
WHERE (u.Reputation > 1000 OR bc.gold_badges > 0)

UNION ALL

SELECT
    NULL                                          AS Id,
    'TOTAL'                                       AS DisplayName,
    SUM(u.Reputation)                             AS Reputation,
    SUM(COALESCE(us.total_posts,0))               AS total_posts,
    SUM(COALESCE(us.questions,0))                 AS questions,
    SUM(COALESCE(us.answers,0))                   AS answers,
    ROUND(AVG(COALESCE(us.avg_score,0)),2)        AS avg_score,
    MAX(us.last_post_date)                        AS last_post_date,
    MAX(us.last_vote_date)                        AS last_vote_date,
    SUM(COALESCE(bc.gold_badges,0))               AS gold_badges,
    SUM(COALESCE(bc.silver_badges,0))             AS silver_badges,
    SUM(COALESCE(bc.bronze_badges,0))             AS bronze_badges,
    NULL                                          AS badge_names,
    NULL                                          AS top_5_tags,
    MAX(ra.recent_post_activity)                 AS recent_post_activity,
    MAX(ra.recent_comment_activity)              AS recent_comment_activity,
    NULL                                          AS reputation_rank,
    NULL                                          AS user_location,
    NULL                                          AS upvotes_last_30d
FROM Users u
LEFT JOIN user_stats     us ON us.Id = u.Id
LEFT JOIN badge_counts   bc ON bc.UserId = u.Id
LEFT JOIN recent_activity ra ON ra.Id = u.Id
HAVING COUNT(u.Id) > 0

ORDER BY Reputation DESC NULLS LAST
LIMIT 100;