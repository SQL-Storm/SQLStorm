-- {"query": "45080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 494}
WITH TagRanking AS (
    SELECT 
        t.TagName, 
        p.Id AS PostId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t
    WHERE p.PostTypeId = 1 AND p.Score > 10
), 
UserContribution AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.BountyAmount) AS TotalBountyAwarded
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 8
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
)
SELECT 
    tr.TagName,
    uc.UserId,
    uc.Reputation,
    tr.PostId,
    tr.Score AS PostScore,
    uc.PostCount,
    uc.AvgPostScore,
    uc.TotalBountyAwarded,
    COUNT(c.Id) AS CommentCount
FROM TagRanking tr
JOIN UserContribution uc ON 1=1
LEFT JOIN Comments c ON c.PostId = tr.PostId
WHERE tr.ScoreRank <= 5
GROUP BY tr.TagName, uc.UserId, uc.Reputation, tr.PostId, tr.Score, uc.PostCount, uc.AvgPostScore, uc.TotalBountyAwarded
ORDER BY tr.Score DESC, uc.Reputation DESC
LIMIT 1000;
