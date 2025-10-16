-- {"query": "15058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 137765, "output_tokens": 40457} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        AVG(u.Reputation) OVER (PARTITION BY DATE_TRUNC('year', b.Date)) AS AnnualAvgReputation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
),
PostAnalytics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS TotalVotes,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.TotalBadges,
    ubc.GoldBadges,
    pa.Id AS TopPostId,
    pa.Score AS TopPostScore,
    pa.ViewCount,
    COALESCE(pa.AnswerCount, 0) AS Answers,
    pa.TotalVotes,
    CASE 
        WHEN pa.PostTypeId = 1 THEN 'Question'
        WHEN pa.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostType,
    ubc.AnnualAvgReputation * 
    (1 + LEAST(pa.Score / 100.0, 0.5)) AS AdjustedReputation
FROM UserBadgeCounts ubc
JOIN PostAnalytics pa ON ubc.UserId = pa.Id
WHERE 
    pa.ScoreRank <= 10 
    AND (
        pa.ViewCount > 1000 
        OR pa.Score > 50
    )
ORDER BY 
    AdjustedReputation DESC, 
    ubc.TotalBadges DESC
LIMIT 100;