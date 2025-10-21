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
        Users AS u
    LEFT JOIN 
        Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges AS b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
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
        Posts AS p
    JOIN 
        Tags AS t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
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
    UserActivity AS ua
CROSS JOIN 
    TopTags AS tt
ORDER BY 
    ua.TotalScore DESC, tt.QuestionCount DESC;