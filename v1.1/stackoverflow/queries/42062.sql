-- {"query": "42062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 524} 
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions, 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers, 
    SUM(p.Score) AS TotalScore, 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.PostId END) AS TotalEdits, 
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS TotalUpvotes, 
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS TotalDownvotes, 
    COUNT(DISTINCT b.Id) AS TotalBadges, 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.PostId END) AS TotalCloseReopenActions, 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.PostId END) AS TotalDeletions, 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.PostId END) AS TotalUndeletions, 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.PostId END) AS TotalLocks, 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.PostId END) AS TotalUnlocks, 
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.PostId END) AS TotalCommunityOwned
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.CreationDate <= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10 AND SUM(p.Score) > 100
ORDER BY 
    TotalScore DESC, TotalPosts DESC
LIMIT 100;