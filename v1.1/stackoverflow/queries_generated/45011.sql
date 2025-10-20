-- {"query": "45011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 25234, "output_tokens": 4433} 
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
        CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tag_list
        JOIN Tags t ON t.TagName = tag_list
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