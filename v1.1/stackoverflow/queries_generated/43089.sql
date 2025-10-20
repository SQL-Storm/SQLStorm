-- {"query": "43089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 752} 

WITH ActiveUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.LastAccessDate > NOW() - INTERVAL '6 months'
    GROUP BY 
        u.Id
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS QuestionCount
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
    ORDER BY 
        QuestionCount DESC
    LIMIT 10
),
UserPostMetrics AS (
    SELECT 
        au.Id AS UserId,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        ActiveUsers au
    JOIN 
        Posts p ON au.Id = p.OwnerUserId
    GROUP BY 
        au.Id
),
BadgeAnalysis AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    upm.TotalScore,
    upm.AvgViewCount,
    upm.LastPostDate,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    tt.TagName AS TopContributedTag
FROM 
    ActiveUsers au
JOIN 
    UserPostMetrics upm ON au.Id = upm.UserId
LEFT JOIN 
    BadgeAnalysis ba ON au.Id = ba.UserId
LEFT JOIN LATERAL (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS Contributions
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        p.OwnerUserId = au.Id
    GROUP BY 
        t.TagName
    ORDER BY 
        Contributions DESC
    LIMIT 1
) tt ON true
ORDER BY 
    upm.TotalScore DESC, au.Reputation DESC
LIMIT 100;
