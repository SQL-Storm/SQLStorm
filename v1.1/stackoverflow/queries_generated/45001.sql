-- {"query": "45001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 379}
WITH UserStats AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.Reputation
), 
TagPopularity AS (
    SELECT 
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagFrequency,
        AVG(Score) AS AvgTagScore
    FROM 
        Posts
    WHERE 
        PostTypeId = 1
    GROUP BY 
        TagName
)
SELECT 
    us.UserId,
    us.Reputation,
    us.PostCount,
    us.VoteCount,
    us.AvgPostScore,
    tp.TagName,
    tp.TagFrequency,
    tp.AvgTagScore
FROM 
    UserStats us
JOIN 
    TagPopularity tp ON tp.TagFrequency > 50
ORDER BY 
    us.Reputation DESC, 
    us.PostCount DESC
LIMIT 100;
