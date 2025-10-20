-- {"query": "45059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 135346, "output_tokens": 24043} 
WITH UserTagInteractions AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.VoteCount) AS TotalVotes,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagRank
    FROM 
        Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT PostId, COUNT(*) AS VoteCount FROM Votes GROUP BY PostId) v ON p.Id = v.PostId
    CROSS APPLY string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') t(TagName)
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, t.TagName
)
SELECT 
    UserId,
    TagName,
    PostCount,
    AvgPostScore,
    TotalVotes,
    TagRank
FROM 
    UserTagInteractions
WHERE 
    TagRank <= 3
    AND PostCount > 5
ORDER BY 
    TotalVotes DESC, 
    AvgPostScore DESC
LIMIT 1000;