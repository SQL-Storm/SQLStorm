-- {"query": "6364.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 724} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivity,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.CreationDate) AS LastPost,
    b.Class,
    b.TagBased,
    ph.RevisionGUID,
    ph.CreationDate AS LastRevision,
    ph.Comment,
    ph.Text,
    CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 
            (SELECT TOP 1 COUNT(*) FROM Posts WHERE PostTypeId = 2 AND ParentId = p.Id)
        ELSE 0
    END AS AcceptedAnswerCount,
    c.Text AS LastComment,
    v.VoteTypeId,
    v.BountyAmount
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
        UserId, 
        MAX(CASE WHEN PostHistoryTypeId IN (1, 2, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35) THEN RevisionGUID ELSE NULL END) AS RevisionGUID,
        MAX(CASE WHEN PostHistoryTypeId IN (1, 2, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35) THEN CreationDate ELSE NULL END) AS CreationDate
     FROM 
        PostHistory 
     GROUP BY 
        UserId) ph ON u.Id = ph.UserId
LEFT JOIN 
    (SELECT 
        PostId, 
        MAX(Id) AS LastCommentId
     FROM 
        Comments 
     GROUP BY 
        PostId) cm ON p.Id = cm.PostId
LEFT JOIN 
    Comments c ON cm.LastCommentId = c.Id AND cm.PostId = c.PostId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= DATEADD(year, -5, GETDATE())
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Id, b.Class, b.TagBased, ph.RevisionGUID, ph.CreationDate, c.Text, v.Id, v.VoteTypeId, v.BountyAmount
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC;
