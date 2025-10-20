WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        tags.tag AS Tag,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgPostScore,
        RANK() OVER (PARTITION BY tags.tag ORDER BY COUNT(*) DESC) AS TagRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL (
        SELECT TRIM(value) AS tag
        FROM UNNEST(string_to_array(
            SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><'
        )) AS t(value)
    ) tags
    WHERE 
        p.PostTypeId = 1
        AND tags.tag IS NOT NULL
    GROUP BY 
        u.Id, u.DisplayName, tags.tag
    HAVING 
        COUNT(*) > 10
)
SELECT 
    t.Tag,
    t.DisplayName,
    t.TagCount,
    t.AvgPostScore,
    v.UpVotes,
    v.DownVotes,
    b.BadgeCount
FROM 
    TopUserTags t
JOIN 
    Users v ON t.UserId = v.Id
LEFT JOIN (
    SELECT 
        UserId, 
        COUNT(*) AS BadgeCount 
    FROM 
        Badges 
    GROUP BY 
        UserId
) b ON t.UserId = b.UserId
WHERE 
    t.TagRank <= 5
ORDER BY 
    t.TagCount DESC, 
    t.AvgPostScore DESC
LIMIT 100;