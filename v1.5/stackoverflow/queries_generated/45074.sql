-- {"query": "45074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 169756, "output_tokens": 29830} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViews,
        COUNT(DISTINCT t.Id) AS UniqueTagCount
    FROM 
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT DISTINCT UserId, TagName 
        FROM PostHistory ph
        CROSS JOIN LATERAL unnest(string_to_array(substring(ph.Text, 2, length(ph.Text)-2), '><')) AS TagName
        JOIN Tags t ON t.TagName = TagName
    ) ut ON u.Id = ut.UserId
    LEFT JOIN Tags t ON ut.TagName = t.TagName
    GROUP BY u.Id, u.Reputation
)
SELECT 
    UserId,
    Reputation,
    PostCount,
    TotalPostScore,
    VoteCount,
    AvgQuestionViews,
    UniqueTagCount,
    RANK() OVER (ORDER BY TotalPostScore DESC) AS PostScoreRank,
    RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank
FROM 
    UserPostStats
WHERE 
    PostCount > 10 
    AND Reputation > 100
ORDER BY 
    TotalPostScore DESC, 
    Reputation DESC
LIMIT 100;