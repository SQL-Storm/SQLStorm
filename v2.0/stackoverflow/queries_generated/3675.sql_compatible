WITH
user_activity AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown')        AS location,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS question_count,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answer_count,
        COUNT(CASE WHEN p.PostTypeId = 3 THEN 1 END) AS wiki_count,
        SUM(p.Score)                           AS total_score,
        AVG(p.Score)                           AS avg_score,
        MAX(p.CreationDate)                    AS last_post_date
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
badge_stats AS (
    SELECT
        b.UserId                             AS user_id,
        COUNT(*)                             AS total_badges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)  AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END)  AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END)  AS bronze_badges,
        STRING_AGG(DISTINCT b.Name, '; ')    AS badge_list
    FROM Badges b
    GROUP BY b.UserId
),
recent_votes AS (
    SELECT
        v.UserId                             AS voter_id,
        COUNT(*)                             AS recent_vote_count,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS downvotes,
        MAX(v.CreationDate)                  AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
    GROUP BY v.UserId
),
user_tag_usage AS (
    SELECT
        p.OwnerUserId                         AS user_id,
        taglist.tag                           AS TagName,
        COUNT(*)                              AS tag_uses,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
    ) AS taglist
    JOIN Tags t ON t.TagName = taglist.tag
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, taglist.tag
),
high_activity_users AS (
    SELECT user_id, 'questions' AS activity_type, question_count AS activity_count
    FROM user_activity
    WHERE question_count >= 50

    UNION ALL

    SELECT user_id, 'answers' AS activity_type, answer_count AS activity_count
    FROM user_activity
    WHERE answer_count >= 200
),
ranked_users AS (
    SELECT
        ua.user_id,
        ua.DisplayName,
        ua.Reputation,
        ua.location,
        ua.question_count,
        ua.answer_count,
        ua.wiki_count,
        ua.total_score,
        ua.avg_score,
        ua.last_post_date,
        bs.total_badges,
        bs.gold_badges,
        bs.silver_badges,
        bs.bronze_badges,
        bs.badge_list,
        rv.recent_vote_count,
        rv.upvotes,
        rv.downvotes,
        rv.last_vote_date,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC) AS reputation_rank,
        RANK()      OVER (ORDER BY ua.total_score DESC) AS score_rank,
        DENSE_RANK()OVER (ORDER BY ua.question_count + ua.answer_count DESC) AS activity_rank
    FROM user_activity ua
    LEFT JOIN badge_stats bs   ON bs.user_id = ua.user_id
    LEFT JOIN recent_votes rv ON rv.voter_id = ua.user_id
)

SELECT
    ru.user_id,
    ru.DisplayName,
    ru.Reputation,
    ru.location,
    ru.question_count,
    ru.answer_count,
    ru.wiki_count,
    ru.total_score,
    ROUND(CAST(ru.avg_score AS DECIMAL), 2)                                      AS avg_score,
    ru.last_post_date,
    ru.total_badges,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    COALESCE(ru.badge_list, 'None')                                     AS badges,
    COALESCE(rv.recent_vote_count,0)                                    AS recent_votes,
    COALESCE(rv.upvotes,0)                                              AS recent_upvotes,
    COALESCE(rv.downvotes,0)                                            AS recent_downvotes,
    rv.last_vote_date,
    ru.reputation_rank,
    ru.score_rank,
    ru.activity_rank,
    (SELECT tt.TagName
       FROM user_tag_usage tt
      WHERE tt.user_id = ru.user_id
        AND tt.tag_rank = 1
      FETCH FIRST 1 ROWS ONLY)                                            AS top_tag,
    CASE
        WHEN COALESCE(ru.gold_badges,0) > 0 THEN 'GoldBadgeHolder'
        WHEN EXISTS (
            SELECT 1 FROM high_activity_users hau
            WHERE hau.user_id = ru.user_id AND hau.activity_type = 'answers' AND hau.activity_count >= 250
        ) THEN 'PowerAnswerer'
        ELSE 'RegularUser'
    END                                                                AS user_category
FROM ranked_users ru
LEFT JOIN recent_votes rv ON rv.voter_id = ru.user_id
WHERE ru.reputation_rank <= 1000
ORDER BY ru.reputation_rank;