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
ExplodedTags AS (
    SELECT
        p.Id AS PostId,
        -- remove surrounding angle brackets and split tags; use GENERATE_SERIES-like approach via recursive CTE for portability
        -- Split tags string of form '<tag1><tag2>' into rows
        TRIM(tag) AS TagName
    FROM Posts p,
    LATERAL (
        SELECT regexp_split_to_table(
            regexp_replace(p.Tags, '^<|>$', '', 'g'),
            '><'
        ) AS tag
    ) s
    WHERE p.PostTypeId = 1
),
PopularTags AS (
    SELECT 
        TagName,
        COUNT(*) AS TagCount
    FROM 
        ExplodedTags
    GROUP BY 
        TagName
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