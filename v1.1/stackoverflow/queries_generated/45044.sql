-- {"query": "45044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 100936, "output_tokens": 17954} 
WITH ActiveUserPosts AS (
    SELECT 
        p.OwnerUserId,
        u.DisplayName,
        COUNT(*) AS TotalPosts,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND u.Reputation > 1000
        AND p.CreationDate > '2018-01-01'
    GROUP BY 
        p.OwnerUserId, u.DisplayName
), 
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AverageTagScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM 
        Posts p
    CROSS JOIN 
        LATERAL (SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) t
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
)
SELECT 
    aup.OwnerUserId,
    aup.DisplayName,
    aup.TotalPosts,
    aup.AveragePostScore,
    tp.TagName AS MostFrequentTag,
    tp.TagCount,
    tp.AverageTagScore,
    aup.LatestPostDate
FROM 
    ActiveUserPosts aup
JOIN 
    TagPopularity tp ON tp.TagCount = (
        SELECT MAX(TagCount)
        FROM TagPopularity
        WHERE TagName IN (
            SELECT unnest(string_to_array(substring((SELECT Tags FROM Posts WHERE OwnerUserId = aup.OwnerUserId LIMIT 1), 2, length((SELECT Tags FROM Posts WHERE OwnerUserId = aup.OwnerUserId LIMIT 1))-2), '><'))
        )
    )
WHERE 
    aup.TotalPosts > 10
ORDER BY 
    aup.AveragePostScore DESC, 
    aup.TotalPosts DESC
LIMIT 100;