-- {"query": "6186.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 575} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id ELSE NULL END) AS TotalPositiveScores,
    MAX(p.Score) AS HighestScore,
    MIN(p.Score) AS LowestScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    MAX(ph.CreationDate) AS LastPostEdit,
    MAX(p.LastActivityDate) AS LastPostActivity,
    b.Class,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         ph.PostId, 
         ph.CreationDate,
         ph.UserId,
         ph.PostHistoryTypeId,
         ph.RevisionGUID,
         ph.Comment,
         ph.Text,
         ph.ContentLicense
     FROM 
         PostHistory ph
     WHERE 
         ph.PostHistoryTypeId = 10) AS latest_close ON u.Id = latest_close.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
         p.Id, 
         COUNT(v.Id) AS VoteCount
     FROM 
         Posts p
     LEFT JOIN 
         Votes v ON p.Id = v.PostId
     GROUP BY 
         p.Id) AS votes_summary ON p.Id = votes_summary.Id
WHERE 
    (p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL)
    OR 
    (p.PostTypeId = 2 AND p.ParentId IN 
        (SELECT 
             p2.Id
         FROM 
             Posts p2
         WHERE 
             p2.PostTypeId = 1 AND p2.ClosedDate IS NOT NULL))
GROUP BY 
    u.Id, b.Id
HAVING 
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) > 0
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
