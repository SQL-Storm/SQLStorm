-- {"query": "43031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 494} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(u.LastAccessDate) AS LastActive
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        AVG(p.ViewCount) AS AvgViewCount
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        t.TagName
    ORDER BY 
        QuestionCount DESC
    LIMIT 10
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalScore,
    ua.TotalBadges,
    tt.TagName,
    tt.QuestionCount,
    tt.AvgScore,
    tt.AvgViewCount
FROM 
    UserActivity ua
CROSS JOIN 
    TopTags tt
ORDER BY 
    ua.TotalScore DESC, tt.QuestionCount DESC;
