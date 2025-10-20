-- {"query": "43088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 585} 
WITH UserReputationStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopContributors AS (
    SELECT 
        urs.Id,
        urs.DisplayName,
        urs.Reputation,
        urs.TotalBadges,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        urs.TotalScore,
        urs.TotalQuestions,
        urs.TotalAnswers,
        ROW_NUMBER() OVER (ORDER BY urs.Reputation DESC, urs.TotalScore DESC) AS RowNum
    FROM 
        UserReputationStats urs
)
SELECT 
    tc.DisplayName,
    tc.Reputation,
    tc.TotalBadges,
    tc.GoldBadges,
    tc.SilverBadges,
    tc.BronzeBadges,
    tc.TotalScore,
    tc.TotalQuestions,
    tc.TotalAnswers,
    ph.Comment AS MostRecentActivityComment,
    ph.CreationDate AS MostRecentActivityDate
FROM 
    TopContributors tc
JOIN 
    Posts p ON tc.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.CreationDate = (
        SELECT MAX(ph2.CreationDate) 
        FROM PostHistory ph2 
        WHERE ph2.PostId = p.Id
    )
WHERE 
    tc.RowNum <= 10
ORDER BY 
    tc.RowNum;