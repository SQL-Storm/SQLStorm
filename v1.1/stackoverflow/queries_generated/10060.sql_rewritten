-- {"query": "10060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 568} 
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
    MIN(u.CreationDate) AS AccountCreationDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastQuestionClosed,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.CreationDate ELSE NULL END) AS LastPostNoticeAdded,
    MAX(CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.RevisionGUID ELSE NULL END) AS LastPostMigratedAway
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    (SELECT 
         ph1.PostId, 
         STRING_AGG(ph2.Comment, ', ') AS CloseReasons
     FROM 
         PostHistory ph1
     JOIN 
         PostHistory ph2 ON ph1.PostId = ph2.PostId AND ph2.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
     WHERE 
         ph1.PostHistoryTypeId = 10
     GROUP BY 
         ph1.PostId) cl ON p.Id = cl.PostId
WHERE 
    u.Reputation > 1000
    AND u.Id NOT IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 3)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;