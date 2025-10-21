WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        SUM(CASE WHEN p.PostTypeId = 3 THEN 1 ELSE 0 END) AS Wikis,
        AVG(u.Reputation) AS AverageReputation
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id,
        u.DisplayName
),
PopularTags AS (
    SELECT 
        t.TagName,
        COUNT(*) AS TagCount
    FROM (
        SELECT
            unnest(string_to_array(Tags, '><')) AS TagName
        FROM 
            Posts
        WHERE 
            PostTypeId = 1
    ) AS t
    GROUP BY 
        t.TagName
    ORDER BY 
        TagCount DESC
    LIMIT 5
)
SELECT 
    us.DisplayName,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.Wikis,
    us.AverageReputation,
    pt.TagName,
    pt.TagCount
FROM 
    UserStats us
CROSS JOIN 
    PopularTags pt
WHERE 
    us.TotalPosts > 10
ORDER BY 
    us.AverageReputation DESC, 
    pt.TagCount DESC;