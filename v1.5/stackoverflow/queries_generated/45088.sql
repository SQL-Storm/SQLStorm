-- {"query": "45088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 201872, "output_tokens": 35729} 
WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName,
        SUM(p.Score) AS TotalTagScore,
        COUNT(p.Id) AS PostCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName, Id FROM Posts) t ON t.Id = p.Id
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, t.TagName
),
TagPerformanceMetrics AS (
    SELECT 
        TagName,
        AVG(TotalTagScore) AS AvgTagScore,
        SUM(PostCount) AS TotalTagPosts,
        COUNT(DISTINCT UserId) AS UniqueUserCount
    FROM 
        ActiveUserTags
    WHERE 
        TagRank <= 3
    GROUP BY 
        TagName
    HAVING 
        COUNT(DISTINCT UserId) > 10
)
SELECT 
    t.TagName,
    t.AvgTagScore,
    t.TotalTagPosts,
    t.UniqueUserCount,
    v.VoteCount,
    pl.LinkCount
FROM 
    TagPerformanceMetrics t
JOIN 
    (SELECT TagName, COUNT(*) AS VoteCount 
     FROM Votes v
     JOIN Posts p ON v.PostId = p.Id
     WHERE v.VoteTypeId IN (2, 3)
     GROUP BY TagName) v ON t.TagName = v.TagName
JOIN 
    (SELECT TagName, COUNT(*) AS LinkCount
     FROM PostLinks pl
     JOIN Posts p ON pl.PostId = p.Id
     GROUP BY TagName) pl ON t.TagName = pl.TagName
ORDER BY 
    t.AvgTagScore DESC, 
    t.TotalTagPosts DESC
LIMIT 50;