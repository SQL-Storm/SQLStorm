-- {"query": "45027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 61938, "output_tokens": 10922} 
WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgPostScore,
        RANK() OVER (PARTITION BY UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) ORDER BY COUNT(*) DESC) AS TagRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        u.Id, u.DisplayName, Tag
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