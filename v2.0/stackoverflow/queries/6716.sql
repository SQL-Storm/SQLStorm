-- {"query": "6716.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 331}
SELECT 
    u.DisplayName,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionsAsked,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswersGiven,
    MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.CreationDate END) AS FirstPostDate,
    MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
    MAX(b.Date) AS LastBadgeEarned,
    ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecentActivityRank
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 10)
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    u.DisplayName,
    u.Id,
    p.LastActivityDate
HAVING 
    COUNT(DISTINCT v.PostId) > 50
ORDER BY 
    TotalVotes DESC, 
    RecentActivityRank ASC;