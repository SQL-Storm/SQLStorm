-- {"query": "42004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 803} 

SELECT 
    u.DisplayName,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TotalScore,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS Downvotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.PostId ELSE NULL END) AS ClosedReopenedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.PostId ELSE NULL END) AS DeletedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.PostId ELSE NULL END) AS UndeletedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.PostId ELSE NULL END) AS LockedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.PostId ELSE NULL END) AS UnlockedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.PostId ELSE NULL END) AS CommunityOwnedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN ph.PostId ELSE NULL END) AS MigratedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.PostId ELSE NULL END) AS ProtectedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 20 THEN ph.PostId ELSE NULL END) AS UnprotectedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 22 THEN ph.PostId ELSE NULL END) AS UnmergedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.PostId ELSE NULL END) AS EditsApplied,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 31 THEN ph.PostId ELSE NULL END) AS MovedToChat,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (33, 34) THEN ph.PostId ELSE NULL END) AS NoticesAddedRemoved,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 50 THEN ph.PostId ELSE NULL END) AS CommunityBumps,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 52 THEN ph.PostId ELSE NULL END) AS HotQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 53 THEN ph.PostId ELSE NULL END) AS RemovedHotQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 66 THEN ph.PostId ELSE NULL END) AS CreatedFromWizard
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.CreationDate <= NOW() - INTERVAL '1 year'
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(p.Id) > 0
ORDER BY 
    TotalPosts DESC, 
    TotalScore DESC, 
    Upvotes DESC, 
    Downvotes DESC
LIMIT 100;
