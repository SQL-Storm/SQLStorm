-- {"query": "52070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 350} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS TotalAnswerScore,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT v.Id) AS TotalVotesReceived,
    COUNT(DISTINCT ph.Id) AS TotalPostEdits,
    COUNT(DISTINCT c.Id) AS TotalCommentsReceived,
    AVG(CASE WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts p2 WHERE p2.Id = p.AcceptedAnswerId) THEN p.Score ELSE NULL END) AS AvgAcceptedAnswerScore
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)  -- UpMod and DownMod
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)  -- Edit types
LEFT JOIN Comments c ON p.Id = c.PostId
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, TotalVotesReceived DESC
LIMIT 100;