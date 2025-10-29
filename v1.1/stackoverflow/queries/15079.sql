-- {"query": "15079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 601}
WITH UserQuestionStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.ViewCount) AS MaxViewCount,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS QuestionCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
AcceptedAnswerRatio AS (
    SELECT 
        q.OwnerUserId,
        COUNT(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 END) * 100.0 / NULLIF(COUNT(DISTINCT q.Id), 0) AS AcceptedAnswerPercentage
    FROM Posts q
    WHERE q.PostTypeId = 1
    GROUP BY q.OwnerUserId
)
SELECT 
    uqs.UserId,
    uqs.DisplayName,
    uqs.QuestionCount,
    uqs.AvgQuestionScore,
    aar.AcceptedAnswerPercentage,
    CASE 
        WHEN uqs.MaxViewCount > 10000 THEN 'High Impact'
        WHEN uqs.MaxViewCount > 5000 THEN 'Medium Impact'
        ELSE 'Low Impact'
    END AS ViewImpactCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uqs.UserId AND b.Class = 1) AS GoldBadgeCount,
    COALESCE(
        (SELECT SUM(v.BountyAmount) 
         FROM Votes v 
         WHERE v.UserId = uqs.UserId AND v.VoteTypeId = 8), 
        0
    ) AS TotalBountyStarted
FROM UserQuestionStats uqs
JOIN AcceptedAnswerRatio aar ON uqs.UserId = aar.OwnerUserId
WHERE uqs.QuestionCount > 5
    AND uqs.AvgQuestionScore > 2
    AND aar.AcceptedAnswerPercentage > 30
ORDER BY 
    uqs.QuestionCount * uqs.AvgQuestionScore DESC
LIMIT 100;
