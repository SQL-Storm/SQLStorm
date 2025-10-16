-- {"query": "15096.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 226495, "output_tokens": 66774} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank,
        AVG(u.Reputation) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate)) AS AverageYearlyReputation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
),
PostActivityStats AS (
    SELECT 
        p.OwnerUserId,
        MAX(p.Score) AS MaxPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews
    FROM Posts p
    WHERE p.CreationDate > (SELECT MIN(CreationDate) FROM Posts) + INTERVAL '1 YEAR'
    GROUP BY p.OwnerUserId
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    pas.QuestionCount,
    pas.AnswerCount,
    ROUND(
        (COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) * 
        (1 + LEAST(ubc.GoldBadgeCount * 0.1, 0.5)),
        2
    ) AS AdjustedVoteScore,
    CASE 
        WHEN ubc.BadgeRank <= 100 THEN 'Top Contributor'
        WHEN pas.TotalViews > 10000 THEN 'Highly Viewed'
        ELSE 'Active User'
    END AS UserCategory
FROM UserBadgeCounts ubc
JOIN PostActivityStats pas ON ubc.UserId = pas.OwnerUserId
LEFT JOIN Users v ON ubc.UserId = v.Id
WHERE 
    pas.MaxPostScore > 10 
    AND (
        COALESCE(pas.QuestionCount, 0) + COALESCE(pas.AnswerCount, 0) > 5
        OR ubc.AverageYearlyReputation > 2000
    )
ORDER BY AdjustedVoteScore DESC
LIMIT 250;