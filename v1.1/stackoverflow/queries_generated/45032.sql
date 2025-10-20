-- {"query": "45032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 73408, "output_tokens": 13328} 
WITH top_tags AS (
    SELECT Tags.TagName, 
           AVG(Posts.Score) as avg_tag_score,
           COUNT(DISTINCT Posts.Id) as post_count
    FROM Tags
    JOIN Posts ON string_to_array(substring(Posts.Tags, 2, length(Posts.Tags)-2), '><') @> ARRAY[Tags.TagName]
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
        COUNT(DISTINCT Posts.Id) as question_count,
        COUNT(DISTINCT Votes.Id) as vote_count,
        MAX(Posts.CreationDate) as last_post_date
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
        ROUND(ua.vote_count * 1.0 / NULLIF(ua.question_count, 0), 2) as engagement_ratio,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ua.Id AND b.Class = 1) as gold_badges
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