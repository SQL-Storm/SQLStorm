WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(p.Id) DESC) AS TagActivityRank
    FROM 
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        -- turn the tag list string like '<tag1><tag2>' into rows: split on '><' after removing outer '<' and '>'
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag_name
        ) tag_vals
        JOIN Tags t ON t.TagName = tag_vals.tag_name
    WHERE 
        p.PostTypeId IN (1, 2)
        AND u.Reputation > 100
    GROUP BY 
        u.Id, t.TagName
    HAVING 
        COUNT(p.Id) > 5
)
SELECT 
    UserId,
    TagName,
    PostCount,
    AvgPostScore,
    TotalViews,
    TagActivityRank
FROM 
    UserTagActivity
WHERE 
    TagActivityRank <= 10
ORDER BY 
    PostCount DESC, 
    AvgPostScore DESC
LIMIT 1000;