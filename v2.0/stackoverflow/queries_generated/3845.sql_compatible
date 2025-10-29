WITH
user_base AS (
    SELECT
        u.Id                                    AS user_id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown')          AS location,
        COUNT(p.Id)                              AS total_posts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS total_questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS total_answers,
        SUM(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS total_score,
        MAX(u.LastAccessDate)                   AS last_seen
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
user_badges AS (
    SELECT
        b.UserId                              AS user_id,
        COUNT(*)                              AS badge_count,
        COUNT(*) FILTER (WHERE b.Class = 1)   AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2)   AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3)   AS bronze_badges,
        STRING_AGG(DISTINCT b.Name, ', ')     AS badge_names
    FROM Badges b
    GROUP BY b.UserId
),
user_recent_activity AS (
    SELECT
        ua.user_id,
        GREATEST(
            COALESCE(MAX(p.LastActivityDate), TIMESTAMP '1970-01-01'),
            COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01'),
            COALESCE(MAX(v.CreationDate), TIMESTAMP '1970-01-01')
        ) AS latest_activity
    FROM user_base ua
    LEFT JOIN Posts p
        ON p.OwnerUserId = ua.user_id
    LEFT JOIN Comments c
        ON c.UserId = ua.user_id
    LEFT JOIN Votes v
        ON v.UserId = ua.user_id
    GROUP BY ua.user_id
),
user_tags AS (
    SELECT
        p.OwnerUserId                           AS user_id,
        COUNT(DISTINCT tag)                      AS distinct_tags_used,
        STRING_AGG(DISTINCT tag, ', ')           AS tag_list
    FROM Posts p,
         LATERAL (
           SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
         ) t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),
user_accepts AS (
    SELECT
        a.OwnerUserId                                 AS user_id,
        COUNT(*) FILTER (WHERE a.Id = q.AcceptedAnswerId) AS accepted_answers,
        COUNT(*)                                      AS total_answers,
        CASE 
            WHEN COUNT(*) = 0 THEN 0
            ELSE ROUND(
                 100.0 * COUNT(*) FILTER (WHERE a.Id = q.AcceptedAnswerId) 
                 / COUNT(*), 2)
        END                                          AS accept_rate_pct
    FROM Posts a
    JOIN Posts q
       ON q.Id = a.ParentId
      AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
ranked_users AS (
    SELECT
        ub.user_id,
        ub.DisplayName,
        ub.Reputation,
        ROW_NUMBER() OVER (ORDER BY ub.Reputation DESC) AS rep_rank
    FROM user_base ub
    ORDER BY ub.Reputation DESC
    LIMIT 20
)
SELECT
    ru.rep_rank,
    ru.user_id,
    ru.DisplayName,
    ru.Reputation,
    ub.badge_count,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    COALESCE(ub.badge_names, '')               AS badge_names,
    ub2.total_posts,
    ub2.total_questions,
    ub2.total_answers,
    ub2.total_score,
    COALESCE(ura.latest_activity, ub2.CreationDate) AS last_activity,
    COALESCE(ut.distinct_tags_used, 0)          AS distinct_tags_used,
    COALESCE(ut.tag_list, '')                  AS tag_list,
    COALESCE(uac.accepted_answers, 0)           AS accepted_answers,
    COALESCE(uac.total_answers, 0)              AS total_answers_given,
    COALESCE(uac.accept_rate_pct, 0)            AS accept_rate_pct,
    CASE
        WHEN ub2.Reputation IS NULL THEN 'Inactive'
        WHEN ub2.Reputation < 1000 THEN 'Newbie'
        WHEN ub2.Reputation BETWEEN 1000 AND 5000 THEN 'Intermediate'
        ELSE 'Veteran'
    END                                         AS reputation_tier,
    ROUND(AVG(ub2.total_score) OVER (ORDER BY ru.rep_rank
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cum_avg_score
FROM ranked_users ru
LEFT JOIN user_badges ub       ON ub.user_id = ru.user_id
LEFT JOIN user_base ub2        ON ub2.user_id = ru.user_id
LEFT JOIN user_recent_activity ura ON ura.user_id = ru.user_id
LEFT JOIN user_tags ut         ON ut.user_id = ru.user_id
LEFT JOIN user_accepts uac     ON uac.user_id = ru.user_id
WHERE ru.rep_rank <= 10

UNION ALL

SELECT
    NULL                                    AS rep_rank,
    b.UserId                                 AS user_id,
    u.DisplayName,
    u.Reputation,
    COUNT(*)                                 AS badge_count,
    COUNT(*) FILTER (WHERE b.Class = 1)      AS gold_badges,
    COUNT(*) FILTER (WHERE b.Class = 2)      AS silver_badges,
    COUNT(*) FILTER (WHERE b.Class = 3)      AS bronze_badges,
    STRING_AGG(DISTINCT b.Name, ', ')        AS badge_names,
    0                                        AS total_posts,
    0                                        AS total_questions,
    0                                        AS total_answers,
    0                                        AS total_score,
    u.LastAccessDate                         AS last_activity,
    0                                        AS distinct_tags_used,
    ''                                       AS tag_list,
    0                                        AS accepted_answers,
    0                                        AS total_answers_given,
    0                                        AS accept_rate_pct,
    'Badge-Only'                             AS reputation_tier,
    NULL                                     AS cum_avg_score
FROM Badges b
JOIN Users u ON u.Id = b.UserId
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = b.UserId)
GROUP BY b.UserId, u.DisplayName, u.Reputation, u.LastAccessDate
ORDER BY reputation_tier DESC, badge_count DESC;