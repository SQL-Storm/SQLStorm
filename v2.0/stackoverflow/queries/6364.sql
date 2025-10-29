-- {"query": "6364.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 724}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS TotalWikis,
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
    SUM(
      CASE 
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 
            (SELECT COUNT(*) FROM Posts sub WHERE sub.PostTypeId = 2 AND sub.ParentId = p.Id)
        ELSE 0
      END
    ) AS AcceptedAnswerCount,
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
        MAX(CASE WHEN PostHistoryTypeId IN (1, 2, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35) THEN RevisionGUID END) AS RevisionGUID,
        MAX(CASE WHEN PostHistoryTypeId IN (1, 2, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35) THEN CreationDate END) AS CreationDate,
        MAX(CASE WHEN PostHistoryTypeId IN (1, 2, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35) THEN Comment END) AS Comment,
        MAX(CASE WHEN PostHistoryTypeId IN (1, 2, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35) THEN Text END) AS Text
     FROM 
        PostHistory 
     GROUP BY 
        UserId) ph ON u.Id = ph.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
        PostId, 
        MAX(Id) AS LastCommentId
     FROM 
        Comments 
     GROUP BY 
        PostId) cm ON p.Id = cm.PostId
LEFT JOIN 
    Comments c ON cm.LastCommentId = c.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Id, b.Class, b.TagBased, ph.RevisionGUID, ph.CreationDate, ph.Comment, ph.Text, c.Text, v.Id, v.VoteTypeId, v.BountyAmount
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC;