-- {"query": "41065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 982} 
SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpVotes,
    AVG(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AvgDownVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id) AS TotalEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 10 AND ph.PostId = p.Id) AS TotalCloses,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 11 AND ph.PostId = p.Id) AS TotalReopens,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 12 AND ph.PostId = p.Id) AS TotalDeletions,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 13 AND ph.PostId = p.Id) AS TotalUndeletions,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 14 AND ph.PostId = p.Id) AS TotalLocks,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 15 AND ph.PostId = p.Id) AS TotalUnlocks,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 16 AND ph.PostId = p.Id) AS TotalCommunityOwned,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 17 AND ph.PostId = p.Id) AS TotalMigrations,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 18 AND ph.PostId = p.Id) AS TotalMerges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 19 AND ph.PostId = p.Id) AS TotalProtections,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 20 AND ph.PostId = p.Id) AS TotalUnprotections,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 24 AND ph.PostId = p.Id) AS TotalSuggestedEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 33 AND ph.PostId = p.Id) AS TotalPostNoticesAdded,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 34 AND ph.PostId = p.Id) AS TotalPostNoticesRemoved,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 52 AND ph.PostId = p.Id) AS TotalSelectedHotQuestions,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 53 AND ph.PostId = p.Id) AS TotalRemovedHotQuestions,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 66 AND ph.PostId = p.Id) AS TotalCommunityBumps
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Posts a ON p.Id = a.ParentId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
ORDER BY 
    p.CreationDate DESC, p.Score DESC, p.ViewCount DESC
LIMIT 100;