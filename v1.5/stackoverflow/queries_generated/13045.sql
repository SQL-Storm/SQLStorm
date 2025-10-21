-- {"query": "13045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 641} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM 
        Users u
    WHERE 
        u.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '90 days'
        AND u.Reputation > 1000
),
UserPostSummary AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionView,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS TotalAnswerScore
    FROM 
        Posts p
    WHERE 
        p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY 
        p.OwnerUserId
),
TopBadgeEarners AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    au.DisplayName,
    au.Reputation,
    COALESCE(ups.QuestionCount, 0) AS Questions,
    COALESCE(ups.AnswerCount, 0) AS Answers,
    COALESCE(ups.AvgQuestionView, 0) AS AvgViews,
    COALESCE(tbe.GoldBadges, 0) AS Gold,
    COALESCE(tbe.SilverBadges, 0) AS Silver,
    COALESCE(tbe.BronzeBadges, 0) AS Bronze,
    (COALESCE(ups.TotalAnswerScore, 0) + COALESCE(tbe.GoldBadges, 0) * 10 + COALESCE(tbe.SilverBadges, 0) * 5 + COALESCE(tbe.BronzeBadges, 0) * 2) AS UserActivityScore
FROM 
    ActiveUsers au
LEFT JOIN 
    UserPostSummary ups ON au.Id = ups.OwnerUserId
LEFT JOIN 
    TopBadgeEarners tbe ON au.Id = tbe.UserId
WHERE 
    au.UserRank <= 100
ORDER BY 
    UserActivityScore DESC, au.Reputation DESC;
