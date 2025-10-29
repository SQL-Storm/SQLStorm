-- {"query": "3238.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2088}
WITH
    usr_stats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            u.LastAccessDate,
            COALESCE(pcnt.total_posts,0)          AS total_posts,
            COALESCE(pcnt.q_posts,0)              AS question_posts,
            COALESCE(pcnt.a_posts,0)              AS answer_posts,
            COALESCE(pcnt.avg_score,0)            AS avg_score,
            COALESCE(bcnt.badge_cnt,0)            AS badge_cnt
        FROM Users u
        LEFT JOIN (
            SELECT
                OwnerUserId                                    AS uid,
                COUNT(*)                                       AS total_posts,
                SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS q_posts,
                SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS a_posts,
                AVG(Score)                                     AS avg_score
            FROM Posts
            GROUP BY OwnerUserId
        ) pcnt ON pcnt.uid = u.Id
        LEFT JOIN (
            SELECT
                UserId,
                COUNT(*) AS badge_cnt
            FROM Badges
            GROUP BY UserId
        ) bcnt ON bcnt.UserId = u.Id
    ),

    ranked_users AS (
        SELECT
            usr_stats.*,
            ROW_NUMBER() OVER (ORDER BY Reputation DESC, avg_score DESC) AS rnk
        FROM usr_stats
    ),

    recent_votes AS (
        SELECT
            UserId,
            COUNT(*) AS votes_30d
        FROM Votes
        WHERE CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 day'
        GROUP BY UserId
    ),

    tag_agg AS (
        SELECT
            t.TagName,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS q_cnt,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS a_cnt,
            SUM(p.Score)                                 AS total_score,
            ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS tag_rnk
        FROM Tags t
        LEFT JOIN Posts p
            ON p.Tags LIKE '%' || t.TagName || '%'
        GROUP BY t.TagName
        HAVING COUNT(p.Id) > 0
    ),

    enriched_users AS (
        SELECT
            ru.Id,
            ru.DisplayName,
            ru.Reputation,
            ru.total_posts,
            ru.question_posts,
            ru.answer_posts,
            ru.avg_score,
            ru.badge_cnt,
            COALESCE(rv.votes_30d,0)                       AS recent_votes,
            CASE
                WHEN ru.LastAccessDate > ru.CreationDate + INTERVAL '1 year' THEN 'Active'
                ELSE 'Dormant'
            END                                            AS activity_status,
            -- Use aggregate over grouped rows instead of DISTINCT within window functions.
            -- Aggregate badge names per user and class by grouping.
            gb.gold_badges,
            sb.silver_badges,
            bb.bronze_badges
        FROM ranked_users ru
        LEFT JOIN recent_votes rv ON rv.UserId = ru.Id
        LEFT JOIN (
            SELECT UserId, STRING_AGG(Name, ', ') AS gold_badges
            FROM (
                SELECT DISTINCT UserId, Name
                FROM Badges
                WHERE Class = 1
            ) x
            GROUP BY UserId
        ) gb ON gb.UserId = ru.Id
        LEFT JOIN (
            SELECT UserId, STRING_AGG(Name, ', ') AS silver_badges
            FROM (
                SELECT DISTINCT UserId, Name
                FROM Badges
                WHERE Class = 2
            ) x
            GROUP BY UserId
        ) sb ON sb.UserId = ru.Id
        LEFT JOIN (
            SELECT UserId, STRING_AGG(Name, ', ') AS bronze_badges
            FROM (
                SELECT DISTINCT UserId, Name
                FROM Badges
                WHERE Class = 3
            ) x
            GROUP BY UserId
        ) bb ON bb.UserId = ru.Id
        WHERE ru.rnk <= 100
    )

SELECT
    eu.Id,
    eu.DisplayName,
    eu.Reputation,
    eu.total_posts,
    eu.question_posts,
    eu.answer_posts,
    eu.avg_score,
    eu.badge_cnt,
    eu.recent_votes,
    eu.activity_status,
    eu.gold_badges,
    eu.silver_badges,
    eu.bronze_badges,
    CAST(NULL AS VARCHAR)      AS tag_name,
    CAST(NULL AS INTEGER)      AS tag_questions,
    CAST(NULL AS INTEGER)      AS tag_answers,
    CAST(NULL AS INTEGER)      AS tag_total_score,
    CAST(NULL AS INTEGER)      AS tag_rank
FROM enriched_users eu
WHERE eu.activity_status = 'Active'

UNION ALL

SELECT
    CAST(NULL AS INTEGER) AS Id,
    '--- TOP TAGS ---' AS DisplayName,
    CAST(NULL AS INTEGER) AS Reputation,
    CAST(NULL AS INTEGER) AS total_posts,
    CAST(NULL AS INTEGER) AS question_posts,
    CAST(NULL AS INTEGER) AS answer_posts,
    CAST(NULL AS DOUBLE PRECISION) AS avg_score,
    CAST(NULL AS INTEGER) AS badge_cnt,
    CAST(NULL AS INTEGER) AS recent_votes,
    CAST(NULL AS VARCHAR) AS activity_status,
    CAST(NULL AS VARCHAR) AS gold_badges,
    CAST(NULL AS VARCHAR) AS silver_badges,
    CAST(NULL AS VARCHAR) AS bronze_badges,
    t.TagName   AS tag_name,
    t.q_cnt     AS tag_questions,
    t.a_cnt     AS tag_answers,
    t.total_score,
    t.tag_rnk   AS tag_rank
FROM tag_agg t
WHERE t.tag_rnk <= 10

ORDER BY
    Reputation DESC,
    recent_votes DESC,
    tag_rank ASC;