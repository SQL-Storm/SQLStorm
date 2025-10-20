-- {"query": "42071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 726} 
SELECT 
    u.DisplayName,
    COUNT(p.Id) AS TotalPosts,
    SUM(p.Score) AS TotalScore,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.PostId END) AS TotalEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.PostId END) AS TotalPostClosuresReopens,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS TotalUpvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS TotalDownvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) AS TotalFavorites,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.PostId END) AS TotalMigrationsAway,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 36 THEN ph.PostId END) AS TotalMigrationsHere,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 52 THEN ph.PostId END) AS TotalHotQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 53 THEN ph.PostId END) AS TotalRemovedHotQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 66 THEN ph.PostId END) AS TotalCreatedFromWizard,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.PostId END) AS TotalCommunityOwned,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.PostId END) AS TotalProtectedQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 20 THEN ph.PostId END) AS TotalUnprotectedQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 22 THEN ph.PostId END) AS TotalUnmergedQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 31 THEN ph.PostId END) AS TotalMovedToChat,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.PostId END) AS TotalPostNoticesAdded,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.PostId END) AS TotalPostNoticesRemoved,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 37 THEN ph.PostId END) AS TotalMergeSources,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 38 THEN ph.PostId END) AS TotalMergeDestinations,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 50 THEN ph.PostId END) AS TotalCommunityBumps
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.PostTypeId IN (1, 2)
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(p.Id) > 10
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC;