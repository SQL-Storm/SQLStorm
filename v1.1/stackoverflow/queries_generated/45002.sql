-- {"query": "45002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 4588, "output_tokens": 761} 
WITH user_tag_activity AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.Votes) AS TotalVotes
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (SELECT 
            PostId, 
            COUNT(Id) AS Votes 
         FROM Votes 
         WHERE VoteTypeId IN (2, 3) 
         GROUP BY PostId) v ON p.Id = v.PostId
    CROSS JOIN 
        LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tag_array
    JOIN 
        Tags t ON t.TagName = tag_array
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 1000
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
    TotalVotes,
    RANK() OVER (PARTITION BY TagName ORDER BY PostCount DESC) AS TagRank
FROM 
    user_tag_activity
WHERE 
    AvgPostScore > 3
ORDER BY 
    TotalVotes DESC, 
    PostCount DESC
LIMIT 250;