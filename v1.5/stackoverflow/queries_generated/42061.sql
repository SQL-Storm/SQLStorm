-- {"query": "42061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 718} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS TotalPosts, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers, 
    SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS TotalScore,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.PostId END) AS TotalVotesReceived,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (24, 25) THEN ph.PostId END) AS TotalEditsMade,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS TotalClosedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.PostId END) AS TotalReopenedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.PostId END) AS TotalDeletedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.PostId END) AS TotalUndeletedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.PostId END) AS TotalLockedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.PostId END) AS TotalUnlockedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.PostId END) AS TotalCommunityOwnedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN ph.PostId END) AS TotalMigratedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.PostId END) AS TotalProtectedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 20 THEN ph.PostId END) AS TotalUnprotectedPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (31, 33, 34) THEN ph.PostId END) AS TotalNoticesAddedOrRemoved,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 50 THEN ph.PostId END) AS TotalCommunityBumps,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 52 THEN ph.PostId END) AS TotalSelectedHotQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 53 THEN ph.PostId END) AS TotalRemovedHotQuestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 66 THEN ph.PostId END) AS TotalCreatedFromWizard
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(p.Id) > 0
ORDER BY 
    TotalScore DESC, TotalPosts DESC, UserId ASC;
