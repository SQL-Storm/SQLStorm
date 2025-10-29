-- {"query": "6816.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 612} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    MAX(u.LastAccessDate) AS LastAccess,
    MIN(u.CreationDate) AS AccountCreated,
    b.Name AS TopBadge,
    CASE 
        WHEN b.Class = 1 THEN 'Gold'
        WHEN b.Class = 2 THEN 'Silver'
        WHEN b.Class = 3 THEN 'Bronze'
        ELSE 'Unknown'
    END AS BadgeClass
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         ph.PostId,
         ph.RevisionGUID,
         ph.CreationDate,
         ph.UserId,
         ph.UserDisplayName,
         ph.Comment,
         MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.CreationDate END) AS FirstTitleChange,
         MAX(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.CreationDate END) AS FirstBodyChange,
         MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
         MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Comment END) AS ReopenReason,
         MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.Comment END) AS PostNoticeAdded,
         MAX(CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.Comment END) AS PostNoticeRemoved
     FROM 
         PostHistory ph
     GROUP BY 
         ph.PostId) ph ON u.Id = ph.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 100
    AND p.CreationDate >= DATEADD(year, -2, GETDATE())
    AND v.VoteTypeId = 8
GROUP BY 
    u.DisplayName, u.Reputation, b.Name
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;
