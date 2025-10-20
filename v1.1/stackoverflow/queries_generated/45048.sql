-- {"query": "45048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 110112, "output_tokens": 19602} 
WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.VoteCount) AS TotalVotes
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (SELECT PostId, COUNT(*) AS VoteCount 
         FROM Votes 
         WHERE VoteTypeId IN (2, 3) 
         GROUP BY PostId) v ON p.Id = v.PostId
    CROSS APPLY 
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag_list(TagName)
    JOIN 
        Tags t ON tag_list.TagName = t.TagName
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, t.TagName
    HAVING 
        COUNT(p.Id) > 5
),
RankedUserTags AS (
    SELECT 
        UserId, 
        DisplayName,
        TagName,
        PostCount,
        AvgPostScore,
        TotalVotes,
        DENSE_RANK() OVER (PARTITION BY UserId ORDER BY PostCount DESC) AS TagRank
    FROM 
        UserTagActivity
)
SELECT 
    DisplayName,
    TagName,
    PostCount,
    AvgPostScore,
    TotalVotes
FROM 
    RankedUserTags
WHERE 
    TagRank <= 3
ORDER BY 
    PostCount DESC, 
    TotalVotes DESC
LIMIT 100;