
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(p.Score) AS TotalScore,
        SUM(DATEDIFF(MINUTE, p.CreationDate, p.LastActivityDate) / 60.0) AS TotalActiveHours
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
),

PostTags AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        LEN(p.Tags) - LEN(REPLACE(p.Tags, '<>', '')) + 1 AS TagCount
    FROM 
        Posts p
)

SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.TotalQuestions,
    ups.TotalAnswers,
    ups.TotalScore,
    ups.TotalActiveHours,
    pt.TagCount
FROM 
    UserPostStats ups
LEFT JOIN 
    PostTags pt ON ups.TotalPosts > 0 AND pt.PostId = ups.TotalPosts
ORDER BY 
    ups.TotalScore DESC;
