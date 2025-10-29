WITH
    user_stats AS (
        SELECT
            u.Id                                   AS user_id,
            u.DisplayName,
            COALESCE(u.Reputation,0)               AS reputation,
            COUNT(DISTINCT b.Id)                   AS badge_cnt,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)   AS upvotes_given,
            MAX(u.LastAccessDate)                 AS last_seen
        FROM Users u
        LEFT JOIN Badges b   ON b.UserId = u.Id
        LEFT JOIN Votes  v   ON v.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    answer_stats AS (
        SELECT
            p.OwnerUserId                         AS user_id,
            COUNT(*)                              AS answer_cnt,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
            SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_cnt,
            MAX(p.CreationDate)                  AS last_answer_dt
        FROM Posts p
        LEFT JOIN Posts q
               ON q.Id = p.ParentId AND q.PostTypeId = 1
        WHERE p.PostTypeId = 2
        GROUP BY p.OwnerUserId
    ),

    tag_activity AS (
        SELECT
            p.OwnerUserId                         AS user_id,
            COUNT(DISTINCT t.Id)                  AS distinct_tag_cnt,
            STRING_AGG(DISTINCT t.TagName, ',')   AS tags_csv
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(
                     trim(both '<>' FROM p.Tags),
                     '><'
                   ) AS tag_name
        ) AS split
        JOIN Tags t ON t.TagName = split.tag_name
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),

    recent_comments AS (
        SELECT
            c.UserId                              AS user_id,
            COUNT(*)                              AS comment_cnt_30d,
            MAX(c.CreationDate)                   AS last_comment_dt
        FROM Comments c
        WHERE c.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
        GROUP BY c.UserId
    ),

    ranked_users AS (
        SELECT
            us.user_id,
            us.DisplayName,
            us.reputation,
            us.badge_cnt,
            us.gold_cnt,
            us.silver_cnt,
            us.bronze_cnt,
            COALESCE(ans.answer_cnt,0)               AS answer_cnt,
            COALESCE(ans.avg_score,0)                AS avg_answer_score,
            COALESCE(ans.accepted_cnt,0)             AS accepted_answer_cnt,
            COALESCE(ta.distinct_tag_cnt,0)         AS distinct_tag_cnt,
            COALESCE(rc.comment_cnt_30d,0)          AS recent_comment_cnt,
            ROW_NUMBER() OVER (ORDER BY us.reputation DESC, us.badge_cnt DESC) AS rep_rank,
            NTILE(4) OVER (ORDER BY us.reputation) AS rep_quartile,
            ta.tags_csv
        FROM user_stats us
        LEFT JOIN answer_stats   ans ON ans.user_id = us.user_id
        LEFT JOIN tag_activity   ta  ON ta.user_id = us.user_id
        LEFT JOIN recent_comments rc ON rc.user_id = us.user_id
    )

SELECT
    ru.user_id,
    ru.DisplayName,
    ru.reputation,
    ru.badge_cnt,
    ru.gold_cnt,
    ru.silver_cnt,
    ru.bronze_cnt,
    ru.answer_cnt,
    ROUND(CAST(ru.avg_answer_score AS numeric),2)   AS avg_answer_score,
    ru.accepted_answer_cnt,
    ru.distinct_tag_cnt,
    ru.recent_comment_cnt,
    ru.rep_rank,
    ru.rep_quartile,
    CASE
        WHEN ru.rep_rank <= 10  THEN 'Top 10'
        WHEN ru.rep_rank <= 100 THEN 'Top 100'
        ELSE 'Other'
    END                                      AS reputation_tier,
    COALESCE(NULLIF(ru.tags_csv,''), 'None') AS tags_sample
FROM ranked_users ru
WHERE ru.reputation > 1000

UNION ALL

SELECT
    ru.user_id,
    ru.DisplayName,
    ru.reputation,
    ru.badge_cnt,
    ru.gold_cnt,
    ru.silver_cnt,
    ru.bronze_cnt,
    ru.answer_cnt,
    ROUND(CAST(ru.avg_answer_score AS numeric),2)   AS avg_answer_score,
    ru.accepted_answer_cnt,
    ru.distinct_tag_cnt,
    ru.recent_comment_cnt,
    ru.rep_rank,
    ru.rep_quartile,
    'Gold-only'                               AS reputation_tier,
    COALESCE(NULLIF(ru.tags_csv,''), 'None') AS tags_sample
FROM ranked_users ru
WHERE ru.reputation = 0 AND ru.gold_cnt > 0

ORDER BY rep_rank
LIMIT 50;