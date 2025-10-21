-- {"query": "45006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 438}
WITH ActiveUserTags AS (
    SELECT u.Id, 
           u.DisplayName, 
           t.TagName, 
           COUNT(p.Id) as PostCount,
           AVG(p.Score) as AvgPostScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (
        SELECT DISTINCT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) as TagName
        FROM Posts
    ) t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(p.Id) > 10
),
TagPerformance AS (
    SELECT TagName, 
           MAX(PostCount) as MaxUserPostCount,
           AVG(AvgPostScore) as OverallTagScore,
           COUNT(DISTINCT Id) as UniqueActiveUsers
    FROM ActiveUserTags
    GROUP BY TagName
)
SELECT 
    tp.TagName, 
    tp.MaxUserPostCount, 
    tp.OverallTagScore, 
    tp.UniqueActiveUsers,
    v.VoteCount,
    p.ViewCount
FROM TagPerformance tp
JOIN (
    SELECT Tags, COUNT(Id) as VoteCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    GROUP BY Tags
) v ON tp.TagName = v.Tags
JOIN (
    SELECT Tags, SUM(ViewCount) as ViewCount
    FROM Posts
    GROUP BY Tags
) p ON tp.TagName = p.Tags
ORDER BY tp.OverallTagScore DESC, tp.UniqueActiveUsers DESC
LIMIT 50;
