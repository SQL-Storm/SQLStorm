WITH user_reputation_ranges AS (
    SELECT 
        CASE 
            WHEN Reputation BETWEEN 0 AND 999 THEN '0-999'
            WHEN Reputation BETWEEN 1000 AND 4999 THEN '1000-4999' 
            WHEN Reputation BETWEEN 5000 AND 19999 THEN '5000-19999'
            WHEN Reputation >= 20000 THEN '20000+'
        END AS reputation_range,
        COUNT(*) AS user_count
    FROM Users
    GROUP BY
        CASE 
            WHEN Reputation BETWEEN 0 AND 999 THEN '0-999'
            WHEN Reputation BETWEEN 1000 AND 4999 THEN '1000-4999' 
            WHEN Reputation BETWEEN 5000 AND 19999 THEN '5000-19999'
            WHEN Reputation >= 20000 THEN '20000+'
        END
),
post_types_with_counts AS (
    SELECT 
        pt.Name AS post_type,
        COUNT(*) AS post_count
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY pt.Name
),
post_activity_summary AS (
    SELECT
        CAST((EXTRACT(EPOCH FROM (MAX(LastActivityDate) - MIN(CreationDate))) / 86400.0) AS NUMERIC(10,2)) AS average_post_age_days,
        AVG(ViewCount) AS average_view_count,
        AVG(AnswerCount) AS average_answer_count,
        AVG(CommentCount) AS average_comment_count,
        AVG(FavoriteCount) AS average_favorite_count
    FROM Posts
),
top_tags AS (
    SELECT 
        t.TagName,
        t.Count AS tag_count
    FROM Tags t
    ORDER BY t.Count DESC
    LIMIT 10
),
badge_distribution AS (
    SELECT
        b.Class,
        COUNT(*) AS badge_count
    FROM Badges b
    GROUP BY b.Class
)
SELECT
    upr.reputation_range,
    upr.user_count,
    ptc.post_type,
    ptc.post_count,
    pas.average_post_age_days,
    pas.average_view_count,
    pas.average_answer_count,
    pas.average_comment_count,
    pas.average_favorite_count,
    tt.TagName,
    tt.tag_count,
    bd.Class,
    bd.badge_count
FROM user_reputation_ranges upr
CROSS JOIN post_types_with_counts ptc
CROSS JOIN post_activity_summary pas
CROSS JOIN top_tags tt
CROSS JOIN badge_distribution bd
ORDER BY upr.reputation_range, ptc.post_type, tt.tag_count DESC, bd.Class;