-- {"query": "45052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 119288, "output_tokens": 21425} 
WITH UserTagInteractions AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN (SELECT Id, (string_to_array(substring(Tags, 2, length(Tags)-2), '><'))[1] AS FirstTag FROM Posts) pt ON pt.Id = p.Id
    JOIN Tags t ON t.TagName = pt.FirstTag
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    WHERE u.Reputation > 1000
    GROUP BY u.Id, t.TagName
), RankedUserTags AS (
    SELECT 
        UserId, 
        TagName, 
        PostCount,
        AvgPostScore,
        VoteCount,
        DENSE_RANK() OVER (PARTITION BY UserId ORDER BY PostCount DESC) AS TagRank
    FROM UserTagInteractions
)
SELECT 
    r.UserId,
    u.DisplayName,
    r.TagName,
    r.PostCount,
    r.AvgPostScore,
    r.VoteCount,
    ROUND(
        (r.PostCount * 0.5) + 
        (r.AvgPostScore * 0.3) + 
        (r.VoteCount * 0.2), 
    2) AS UserTagContributionScore
FROM RankedUserTags r
JOIN Users u ON u.Id = r.UserId
WHERE r.TagRank <= 3
ORDER BY UserTagContributionScore DESC
LIMIT 100;