WITH RECURSIVE
    recent_posts AS (
        SELECT  p.Id,
                p.OwnerUserId,
                p.PostTypeId,
                p.CreationDate,
                CASE 
                    WHEN p.Tags IS NOT NULL 
                    THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2)
                    ELSE NULL
                END AS raw_tags
        FROM    Posts p
        WHERE   p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
    ),
    user_answer_score AS (
        SELECT  p.OwnerUserId          AS user_id,
                COUNT(*)               AS answer_cnt,
                SUM(p.Score)           AS total_score
        FROM    Posts p
        WHERE   p.PostTypeId = 2
        GROUP BY p.OwnerUserId
    ),
    user_badge_counts AS (
        SELECT  b.UserId               AS user_id,
                SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
                SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
                SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt
        FROM    Badges b
        GROUP BY b.UserId
    ),
    tag_explode AS (
        SELECT  u.Id                                    AS user_id,
                UNNEST(string_to_array(rp.raw_tags, '><')) AS tag,
                p.Score                                 AS post_score,
                ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS rn
        FROM    Users u
        JOIN    Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
        JOIN    recent_posts rp ON rp.Id = p.Id
        WHERE   rp.raw_tags IS NOT NULL
    ),
    top_tags AS (
        SELECT  user_id,
                tag,
                post_score
        FROM    tag_explode
        WHERE   rn <= 3
    )
SELECT
    u.Id                                              AS user_id,
    COALESCE(u.DisplayName, 'Anonymous')              AS display_name,
    COALESCE(uas.answer_cnt, 0)                       AS answer_count,
    COALESCE(uas.total_score, 0)                      AS total_answer_score,
    COALESCE(ubc.gold_cnt, 0)                         AS gold_badges,
    COALESCE(ubc.silver_cnt, 0)                       AS silver_badges,
    COALESCE(ubc.bronze_cnt, 0)                       AS bronze_badges,
    STRING_AGG(DISTINCT tt.tag, ', ')                 AS top_tags,
    (SELECT COUNT(*) 
     FROM   Comments c 
     WHERE  c.UserId = u.Id 
       AND  c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days') AS recent_comments,
    (SELECT MAX(v.CreationDate) 
     FROM   Votes v 
     WHERE  v.UserId = u.Id)                           AS last_vote_date,
    CASE
        WHEN u.Reputation >= 20000 THEN 'Legendary'
        WHEN u.Reputation >= 10000 THEN 'Trusted'
        WHEN u.Reputation >= 2000  THEN 'Experienced'
        ELSE 'Newbie'
    END                                               AS reputation_level
FROM    Users u
LEFT JOIN user_answer_score uas   ON uas.user_id   = u.Id
LEFT JOIN user_badge_counts ubc   ON ubc.user_id   = u.Id
LEFT JOIN top_tags tt             ON tt.user_id    = u.Id
WHERE   u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
GROUP BY
    u.Id, u.DisplayName, u.Reputation,
    uas.answer_cnt, uas.total_score,
    ubc.gold_cnt, ubc.silver_cnt, ubc.bronze_cnt
HAVING COUNT(*) > 0

UNION ALL

SELECT
    -1                                                AS user_id,
    'Aggregated_Totals'                               AS display_name,
    SUM(COALESCE(uas.answer_cnt,0))                   AS answer_count,
    SUM(COALESCE(uas.total_score,0))                  AS total_answer_score,
    SUM(COALESCE(ubc.gold_cnt,0))                     AS gold_badges,
    SUM(COALESCE(ubc.silver_cnt,0))                   AS silver_badges,
    SUM(COALESCE(ubc.bronze_cnt,0))                   AS bronze_badges,
    NULL                                              AS top_tags,
    NULL                                              AS recent_comments,
    NULL                                              AS last_vote_date,
    NULL                                              AS reputation_level
FROM    Users u
LEFT JOIN user_answer_score uas   ON uas.user_id = u.Id
LEFT JOIN user_badge_counts ubc   ON ubc.user_id = u.Id
WHERE   u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year';