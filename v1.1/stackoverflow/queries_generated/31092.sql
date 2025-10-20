-- {"query": "31092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 374} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        SUM(CASE WHEN p.PostTypeId IN (4, 5) THEN 1 ELSE 0 END) AS TagWikis,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId 
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id
),
PopularTags AS (
    SELECT 
        TRIM(both '<>' FROM UNNEST(string_to_array(SUBSTRING(tags, 2, LENGTH(tags) - 2), '><'))) AS Tag,
        COUNT(p.Id) AS TagUsage
    FROM 
        Posts p
    WHERE 
        p.Tags IS NOT NULL 
    GROUP BY 
        Tag
    ORDER BY 
        TagUsage DESC
    LIMIT 10
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.TagWikis,
    ups.TotalScore,
    ups.AvgViewCount,
    ups.LastPostDate,
    pt.Tag AS PopularTag,
    pt.TagUsage
FROM 
    UserPostStats ups
CROSS JOIN 
    PopularTags pt
ORDER BY 
    ups.TotalScore DESC, ups.LastPostDate DESC
LIMIT 50;
