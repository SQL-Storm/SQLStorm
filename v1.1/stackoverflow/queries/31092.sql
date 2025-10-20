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
        u.Id,
        u.DisplayName
),
PopularTags AS (
    SELECT 
        TRIM(BOTH '<>' FROM t.tag) AS Tag,
        COUNT(p.Id) AS TagUsage
    FROM 
        Posts p,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS t(tag)
    WHERE 
        p.Tags IS NOT NULL 
    GROUP BY 
        t.tag
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