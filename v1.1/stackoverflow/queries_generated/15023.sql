-- {"query": "15023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 699}
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank,
        DENSE_RANK() OVER (PARTITION BY u.Location ORDER BY COUNT(DISTINCT b.Id) DESC) AS LocalBadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Location
),
PostActivityAnalysis AS (
    SELECT 
        p.OwnerUserId,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.LastActivityDate) AS MostRecentActivity,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY p.OwnerUserId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.BadgeRank,
    pa.QuestionCount,
    pa.AnswerCount,
    pa.AvgPostScore,
    pa.TotalVotes,
    COALESCE(pa.AvgPostScore, 0) * SQRT(COALESCE(pa.TotalVotes, 0)) AS EngagementMetric,
    CASE 
        WHEN ubs.TotalBadges > 10 AND pa.QuestionCount > 5 THEN 'High Impact User'
        WHEN ubs.TotalBadges > 5 AND pa.AnswerCount > 10 THEN 'Consistent Contributor'
        ELSE 'Regular User'
    END AS UserCategory
FROM UserBadgeStats ubs
FULL OUTER JOIN PostActivityAnalysis pa ON ubs.UserId = pa.OwnerUserId
WHERE 
    ubs.TotalBadges > 0 
    AND (pa.QuestionCount > 0 OR pa.AnswerCount > 0)
ORDER BY EngagementMetric DESC
LIMIT 500;
