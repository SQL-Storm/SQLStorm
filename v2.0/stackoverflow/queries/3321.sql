-- {"query": "3321.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2095}
WITH 
user_activity AS (
    SELECT 
        u.Id                               AS user_id,
        COUNT(p.Id)                        AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers,
        MAX(p.CreationDate)                AS last_post_date,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS up_votes_given,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS down_votes_given,
        AVG(p.Score)                       AS avg_post_score
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.UserId = u.Id
    GROUP BY u.Id
),
badge_stats AS (
    SELECT 
        b.UserId                            AS user_id,
        COUNT(*)                            AS total_badges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze,
        STRING_AGG(DISTINCT b.Name, ', ')   AS badge_names
    FROM Badges b
    GROUP BY b.UserId
),
recent_comments AS (
    SELECT 
        c.UserId                             AS user_id,
        STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 50), ' | ') AS recent_comments,
        MAX(c.CreationDate)                  AS latest_comment_date
    FROM Comments c
    WHERE c.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30 days')
    GROUP BY c.UserId
),
user_tags AS (
    SELECT 
        up.user_id,
        STRING_AGG(t.TagName, ', ')          AS top_tags
    FROM (
        SELECT 
            p.OwnerUserId                     AS user_id,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ) up
    JOIN Tags t ON t.TagName = up.tag
    GROUP BY up.user_id
)
SELECT 
    u.Id                                              AS user_id,
    u.DisplayName,
    u.Reputation,
    ua.total_posts,
    ua.questions,
    ua.answers,
    ua.last_post_date,
    ua.up_votes_given,
    ua.down_votes_given,
    ua.avg_post_score,
    COALESCE(bs.total_badges,0)                       AS total_badges,
    COALESCE(bs.gold,0)                               AS gold_badges,
    COALESCE(bs.silver,0)                             AS silver_badges,
    COALESCE(bs.bronze,0)                             AS bronze_badges,
    bs.badge_names,
    rc.recent_comments,
    rc.latest_comment_date,
    ut.top_tags,
    RANK() OVER (ORDER BY u.Reputation DESC, ua.total_posts DESC) AS reputation_rank,
    CASE 
        WHEN u.Reputation IS NULL THEN 'Unranked'
        WHEN u.Reputation >= 20000 THEN 'Legendary'
        WHEN u.Reputation >= 10000 THEN 'Expert'
        WHEN u.Reputation >= 5000  THEN 'Veteran'
        WHEN u.Reputation >= 1000  THEN 'Seasoned'
        ELSE 'Newbie'
    END                                               AS reputation_tier
FROM Users u
LEFT JOIN user_activity   ua ON ua.user_id = u.Id
LEFT JOIN badge_stats     bs ON bs.user_id = u.Id
LEFT JOIN recent_comments rc ON rc.user_id = u.Id
LEFT JOIN user_tags       ut ON ut.user_id = u.Id
WHERE 
    (u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1 year') OR u.Reputation IS NOT NULL)
    AND (u.DisplayName IS NOT NULL AND u.DisplayName <> '')
    AND (u.Reputation > 0 OR bs.total_badges IS NOT NULL)
ORDER BY u.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;