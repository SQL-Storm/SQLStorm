WITH UserActivityMetrics AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        MAX(u.Reputation) AS MaxReputation
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE 
        u.LastAccessDate > timestamp '2024-10-01 12:34:56' - interval '1 year'
    GROUP BY 
        u.Id, u.DisplayName
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM 
        Tags t
    JOIN 
        Posts p ON POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
    WHERE 
        p.CreationDate > timestamp '2024-10-01 12:34:56' - interval '6 months'
    GROUP BY 
        t.TagName
    ORDER BY 
        PostCount DESC
    LIMIT 10
)
SELECT 
    uam.UserId,
    uam.DisplayName,
    uam.TotalPosts,
    uam.TotalQuestions,
    uam.TotalAnswers,
    uam.AvgPostScore,
    uam.TotalEdits,
    uam.MaxReputation,
    tt.TagName AS TopContributedTag
FROM 
    UserActivityMetrics uam
LEFT JOIN 
    (SELECT 
        ph.UserId, 
        t.TagName, 
        ROW_NUMBER() OVER (PARTITION BY ph.UserId ORDER BY COUNT(*) DESC) AS rn
     FROM 
        PostHistory ph
     JOIN 
        Posts p ON ph.PostId = p.Id
     JOIN 
        Tags t ON POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
     WHERE 
        ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
     GROUP BY 
        ph.UserId, t.TagName) AS UserTopTags
ON 
    uam.UserId = UserTopTags.UserId AND UserTopTags.rn = 1
LEFT JOIN
    TopTags tt ON tt.TagName = UserTopTags.TagName
WHERE 
    uam.TotalPosts > (SELECT AVG(TotalPosts) FROM UserActivityMetrics)
ORDER BY 
    uam.TotalPosts DESC, uam.AvgPostScore DESC;