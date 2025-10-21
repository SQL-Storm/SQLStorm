-- {"query": "42020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 900} 
SELECT 
    u.DisplayName,
    COUNT(p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.PostId END) AS TotalClosedReopened,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS TotalDownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) AS TotalFavorites,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.PostId END) AS TotalMigratedAway,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 36 THEN ph.PostId END) AS TotalMigratedHere,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.PostId END) AS TotalDeleted,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.PostId END) AS TotalUndeleted,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.PostId END) AS TotalLocked,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 15 THEN ph.PostId END) AS TotalUnlocked,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.PostId END) AS TotalCommunityOwned,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.PostId END) AS TotalProtected,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 20 THEN ph.PostId END) AS TotalUnprotected,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 22 THEN ph.PostId END) AS TotalUnmerged,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 31 THEN ph.PostId END) AS TotalMovedToChat,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.PostId END) AS TotalNoticeAdded,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 34 THEN ph.PostId END) AS TotalNoticeRemoved,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 35 THEN ph.PostId END) AS TotalMigratedAway,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 36 THEN ph.PostId END) AS TotalMigratedHere,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 37 THEN ph.PostId END) AS TotalMergeSource,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 38 THEN ph.PostId END) AS TotalMergeDestination,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 50 THEN ph.PostId END) AS TotalCommunityBump,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 52 THEN ph.PostId END) AS TotalSelectedHotQuestion,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 53 THEN ph.PostId END) AS TotalRemovedHotQuestion,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 66 THEN ph.PostId END) AS TotalCreatedFromWizard
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.CreationDate >= '2020-01-01' AND u.CreationDate < '2021-01-01'
GROUP BY 
    u.DisplayName
ORDER BY 
    TotalScore DESC, TotalPosts DESC
LIMIT 100;