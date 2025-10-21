-- {"query": "14098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1013}
SELECT 
    DENSE_RANK() OVER (ORDER BY COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN 1 END) DESC) AS CloseReopenUndeleteRankingByUser,
    u.DisplayName,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN 1 END) AS CloseReopenUndeleteCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) AND ph.Comment IS NOT NULL THEN ph.Comment END) AS CloseReopenUndeleteWithReason,
    ROUND(100.0 * COUNT(CASE WHEN ph.PostHistoryTypeId IN (11, 13, 20) THEN 1 END) / NULLIF(COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN 1 END), 0), 2) AS ReopenedPercentage,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS INT) ELSE 0 END), 0) AS TotalCloseVotesByType,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('101', '102', '103', '104', '105') THEN 1 ELSE 0 END) AS CurrentCloseVotesByType,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment NOT IN ('101', '102', '103', '104', '105') THEN 1 ELSE 0 END) AS OldCloseVotesByType,
    ROUND(100.0 * SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('101', '102', '103', '104', '105') THEN 1 ELSE 0 END) / NULLIF(COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0), 0), 2) AS CurrentCloseVotePercentage,
    ROUND(100.0 * SUM(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment NOT IN ('101', '102', '103', '104', '105') THEN 1 ELSE 0 END) / NULLIF(COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0), 0), 2) AS OldCloseVotePercentage,
    COUNT(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 END) AS UpDownVoteCount,
    ROUND(100.0 * COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) / NULLIF(COUNT(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 END), 0), 2) AS UpVotePercentage,
    ROUND(100.0 * COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) / NULLIF(COUNT(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 END), 0), 2) AS DownVotePercentage
FROM 
    Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
GROUP BY 
    u.DisplayName
ORDER BY 
    CloseReopenUndeleteRankingByUser;
