-- {"query": "45040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 276}
WITH TopTagUsers AS (
    SELECT t.TagName, u.Id, u.DisplayName, COUNT(*) as TagPostCount,
           RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(*) DESC) as UserRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) as TagName, Id FROM Posts) t ON t.Id = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, u.Id, u.DisplayName
)
SELECT 
    TagName,
    STRING_AGG(DisplayName || ' (' || TagPostCount || ' posts)', ', ' ORDER BY UserRank) as TopContributors,
    COUNT(DISTINCT Id) as UniqueContributors,
    AVG(TagPostCount) as AveragePostsPerUser
FROM TopTagUsers
WHERE UserRank <= 5
GROUP BY TagName
ORDER BY UniqueContributors DESC, AveragePostsPerUser DESC
LIMIT 100;
