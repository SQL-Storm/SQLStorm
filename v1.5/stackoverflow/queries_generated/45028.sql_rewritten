-- {"query": "45028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 64232, "output_tokens": 11387} 
WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        COUNT(*) AS TagPostCount,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t ON true
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
),
UserTagPerformance AS (
    SELECT 
        UserId, 
        DisplayName,
        STRING_AGG(TagName || ':' || TagPostCount, ', ' ORDER BY TagPostCount DESC) AS TopTags,
        SUM(TagPostCount) AS TotalTagPosts,
        COUNT(DISTINCT TagName) AS UniqueTagCount
    FROM TopUserTags
    WHERE TagRank <= 3
    GROUP BY UserId, DisplayName
)
SELECT 
    utp.UserId,
    utp.DisplayName,
    utp.TotalTagPosts,
    utp.UniqueTagCount,
    utp.TopTags,
    ROUND(u.Reputation / EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) * 86400, 2) AS RepPerDay,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = utp.UserId AND p.Score > 10) AS HighScoringPosts
FROM UserTagPerformance utp
JOIN Users u ON utp.UserId = u.Id
WHERE utp.TotalTagPosts > 50
ORDER BY utp.TotalTagPosts DESC, RepPerDay DESC
LIMIT 100;