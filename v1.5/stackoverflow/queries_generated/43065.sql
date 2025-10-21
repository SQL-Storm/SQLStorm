-- {"query": "43065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 599} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalPostClosed,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalPostReopened,
        AVG(u.Reputation) AS AvgReputation
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId
    WHERE 
        u.LastAccessDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 year'
    GROUP BY 
        u.Id
),
HighActivityUsers AS (
    SELECT 
        UserId
    FROM 
        UserActivity
    WHERE 
        TotalQuestions > (SELECT AVG(TotalQuestions) FROM UserActivity)
        OR TotalAnswers > (SELECT AVG(TotalAnswers) FROM UserActivity)
        OR TotalPostClosed > (SELECT AVG(TotalPostClosed) FROM UserActivity)
)
SELECT 
    u.DisplayName,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalBadges,
    COUNT(DISTINCT p.Id) AS PostsEdited,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT v.Id) AS VotesCast
FROM 
    HighActivityUsers hau
JOIN 
    Users u ON hau.UserId = u.Id
LEFT JOIN 
    UserActivity ua ON hau.UserId = ua.UserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN 
    Posts p ON ph.PostId = p.Id
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
GROUP BY 
    u.DisplayName, ua.TotalQuestions, ua.TotalAnswers, ua.TotalBadges
ORDER BY 
    PostsEdited DESC, CommentsMade DESC, VotesCast DESC
LIMIT 10;
