WITH top_tags AS (
    SELECT
        Tags.TagName,
        AVG(Posts.Score) AS avg_tag_score,
        COUNT(DISTINCT Posts.Id) AS post_count
    FROM Tags
    JOIN Posts ON ARRAY_TO_STRING(STRING_TO_ARRAY(SUBSTRING(Posts.Tags FROM 2 FOR CHAR_LENGTH(Posts.Tags) - 2), '<>'), ',') LIKE '%' || Tags.TagName || '%'
    WHERE Posts.PostTypeId = 1
    GROUP BY Tags.TagName
    HAVING COUNT(DISTINCT Posts.Id) > 1000
    ORDER BY avg_tag_score DESC
    LIMIT 50
),
user_activity AS (
    SELECT
        Users.Id,
        Users.DisplayName,
        COUNT(DISTINCT Posts.Id) AS question_count,
        COUNT(DISTINCT Votes.Id) AS vote_count,
        MAX(Posts.CreationDate) AS last_post_date
    FROM Users
    LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
    LEFT JOIN Votes ON Users.Id = Votes.UserId
    WHERE Posts.PostTypeId = 1
    GROUP BY Users.Id, Users.DisplayName
),
complex_metrics AS (
    SELECT
        ua.Id,
        ua.DisplayName,
        ua.question_count,
        ua.vote_count,
        ROUND(ua.vote_count * 1.0 / NULLIF(ua.question_count, 0), 2) AS engagement_ratio,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.Id AND b.Class = 1) AS gold_badges
    FROM user_activity ua
    WHERE ua.question_count > 10
)
SELECT
    tt.TagName,
    cm.DisplayName,
    cm.question_count,
    cm.vote_count,
    cm.engagement_ratio,
    cm.gold_badges,
    tt.avg_tag_score,
    tt.post_count
FROM top_tags tt
CROSS JOIN complex_metrics cm
WHERE cm.engagement_ratio > 2
ORDER BY cm.gold_badges DESC, cm.engagement_ratio DESC
LIMIT 100;