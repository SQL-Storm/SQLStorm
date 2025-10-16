-- {"query": "13059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 664} 

WITH UserScores AS (
    SELECT 
        OwnerUserId,
        SUM(CASE WHEN PostTypeId = 1 THEN Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswerCount
    FROM 
        Posts
    WHERE 
        OwnerUserId IS NOT NULL
    GROUP BY 
        OwnerUserId
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COALESCE(us.TotalQuestionScore, 0) AS TotalQuestionScore,
        COALESCE(us.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(us.QuestionCount, 0) AS QuestionCount,
        COALESCE(us.AnswerCount, 0) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY COALESCE(us.TotalQuestionScore, 0) + COALESCE(us.TotalAnswerScore, 0) DESC) AS Rank
    FROM 
        Users u
    LEFT JOIN 
        UserScores us ON u.Id = us.OwnerUserId
    WHERE 
        u.Reputation > 1000
),
BadgeAggregates AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    ur.UserId,
    ur.Reputation,
    ur.TotalQuestionScore,
    ur.TotalAnswerScore,
    ur.QuestionCount,
    ur.AnswerCount,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    CONCAT(u.DisplayName, ' has ', COALESCE(ba.GoldBadges, 0), ' gold badges') AS BadgeSummary
FROM 
    UserReputation ur
LEFT JOIN 
    BadgeAggregates ba ON ur.UserId = ba.UserId
JOIN 
    Users u ON ur.UserId = u.Id
WHERE 
    ur.Rank <= 100 AND 
    (
        SELECT 
            COUNT(*) 
        FROM 
            Comments c 
        WHERE 
            c.UserId = ur.UserId AND 
            LENGTH(c.Text) > 100
    ) > 5
ORDER BY 
    ur.TotalQuestionScore DESC, 
    ur.TotalAnswerScore DESC;
