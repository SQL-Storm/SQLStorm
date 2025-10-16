-- {"query": "2083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 415} 

WITH RecentActiveUsers AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        LastAccessDate,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS Rank
    FROM 
        Users
    WHERE 
        LastAccessDate > NOW() - INTERVAL '30 days'
),
UserPostCounts AS (
    SELECT 
        OwnerUserId,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM 
        Posts
    GROUP BY 
        OwnerUserId
),
UserBadges AS (
    SELECT 
        UserId, 
        COUNT(*) AS BadgeCount,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    u.DisplayName,
    u.Reputation,
    COALESCE(uc.QuestionCount, 0) AS QuestionsPosted,
    COALESCE(uc.AnswerCount, 0) AS AnswersPosted,
    COALESCE(ub.BadgeCount, 0) AS TotalBadges,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    r.Rank
FROM 
    RecentActiveUsers r
LEFT JOIN 
    UserPostCounts uc ON r.Id = uc.OwnerUserId
LEFT JOIN 
    UserBadges ub ON r.Id = ub.UserId
WHERE 
    r.Rank <= 10
ORDER BY 
    r.Rank;
