-- {"query": "45034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 77996, "output_tokens": 14027} 
WITH high_impact_users AS (
    SELECT UserId, COUNT(DISTINCT Posts.Id) as posts_count, 
           AVG(Posts.Score) as avg_post_score,
           SUM(AnswerCount) as total_answers_received
    FROM Posts
    JOIN Users ON Posts.OwnerUserId = Users.Id
    WHERE Posts.PostTypeId = 1 AND Users.Reputation > 10000
    GROUP BY UserId
), tag_complexity AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) as tag,
        COUNT(DISTINCT Posts.Id) as tag_post_count,
        AVG(Posts.ViewCount) as avg_view_count,
        MAX(Posts.Score) as max_tag_score
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY tag
)
SELECT 
    u.DisplayName,
    hiu.posts_count,
    hiu.avg_post_score,
    hiu.total_answers_received,
    tc.tag,
    tc.tag_post_count,
    tc.avg_view_count
FROM high_impact_users hiu
JOIN Users u ON hiu.UserId = u.Id
JOIN tag_complexity tc ON 
    EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.Tags LIKE '%' || tc.tag || '%'
    )
ORDER BY hiu.posts_count * tc.tag_post_count DESC
LIMIT 100;