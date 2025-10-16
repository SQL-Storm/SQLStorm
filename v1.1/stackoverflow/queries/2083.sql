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
        LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
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
        COUNT(CASE WHEN "badges"."class" = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN "badges"."class" = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN "badges"."class" = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges AS badges
    GROUP BY 
        UserId
)
SELECT 
    r.DisplayName,
    r.Reputation,
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