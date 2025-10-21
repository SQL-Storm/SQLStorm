-- {"query": "45024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 439}
WITH PopularTags AS (
    SELECT t.TagName, 
           PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.Score) AS high_percentile_score,
           AVG(p.ViewCount) AS avg_views,
           COUNT(DISTINCT p.OwnerUserId) AS unique_authors
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 500
    ORDER BY unique_authors DESC, avg_views DESC
    LIMIT 20
),
HighImpactUsers AS (
    SELECT u.Id, u.Reputation, 
           COUNT(DISTINCT p.Id) AS posts_count,
           COUNT(DISTINCT v.Id) AS votes_given,
           SUM(p.Score) AS total_post_score
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
)
SELECT 
    pt.TagName,
    pt.high_percentile_score,
    pt.avg_views,
    pt.unique_authors,
    hi.posts_count,
    hi.votes_given,
    hi.total_post_score,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.LinkTypeId = 3) AS total_duplicate_links
FROM PopularTags pt
CROSS JOIN HighImpactUsers hi
ORDER BY pt.unique_authors * hi.total_post_score DESC
LIMIT 100;
