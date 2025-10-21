-- {"query": "45045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 373}
WITH TagPopularity AS (
    SELECT 
        UNNEST(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS tag,
        AVG(Score) AS avg_score,
        COUNT(*) AS post_count
    FROM Posts 
    WHERE PostTypeId = 1
    GROUP BY tag
    HAVING COUNT(*) > 100
),
UserContribution AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS question_count,
        COUNT(DISTINCT v.Id) AS vote_count,
        AVG(p.Score) AS avg_post_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 50
)
SELECT 
    tp.tag,
    tp.avg_score AS tag_avg_score,
    tp.post_count,
    uc.DisplayName AS top_contributor,
    uc.question_count,
    uc.vote_count,
    uc.avg_post_score
FROM TagPopularity tp
JOIN UserContribution uc ON uc.avg_post_score > tp.avg_score * 1.5
ORDER BY tp.post_count DESC, uc.question_count DESC
LIMIT 100;
