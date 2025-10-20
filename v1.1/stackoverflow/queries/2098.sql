-- {"query": "2098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 416} 
WITH TopUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    WHERE 
        u.CreationDate > '2020-01-01'
),
HighRepUsers AS (
    SELECT 
        UserId, 
        DisplayName
    FROM 
        TopUsers
    WHERE 
        ReputationRank <= 100
),
PostSummary AS (
    SELECT 
        p.OwnerUserId, 
        COUNT(*) AS TotalPosts, 
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers
    FROM 
        Posts p
    WHERE 
        p.CreationDate BETWEEN '2020-01-01' AND '2023-01-01'
    GROUP BY 
        p.OwnerUserId
)
SELECT 
    hru.UserId, 
    hru.DisplayName, 
    ps.TotalPosts, 
    ps.TotalQuestions, 
    ps.TotalAnswers,
    COALESCE(b.BadgeCount, 0) AS TotalBadges,
    ROUND(AVG(c.Score) OVER (PARTITION BY c.PostId), 2) AS AvgCommentScore
FROM 
    HighRepUsers hru
LEFT JOIN 
    PostSummary ps ON hru.UserId = ps.OwnerUserId
LEFT JOIN 
    (SELECT UserId, COUNT(Id) AS BadgeCount FROM Badges WHERE Class IN (1, 2) GROUP BY UserId) b ON hru.UserId = b.UserId
LEFT JOIN 
    Comments c ON hru.UserId = c.UserId
WHERE 
    (ps.TotalQuestions IS NOT NULL OR ps.TotalAnswers IS NOT NULL)
ORDER BY 
    ps.TotalPosts DESC, TotalBadges DESC;