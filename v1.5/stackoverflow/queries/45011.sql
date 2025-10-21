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
        CROSS JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag_list(tag)
        JOIN Tags t ON t.TagName = tag_list.tag
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