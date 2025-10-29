-- {"query": "6356.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 464}
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalTitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN p.Id END) AS TotalBodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN p.Id END) AS TotalCloseVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN p.Id END) AS TotalReopenVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id END) AS TotalDownVotes,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestAccountCreation,
    AVG((EXTRACT(EPOCH FROM u.LastAccessDate) - EXTRACT(EPOCH FROM u.CreationDate)) / 86400.0) AS AvgDaysBetweenAccesses,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS MostFrequentTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 2, 10, 11)
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Badges 
        WHERE "badges"."class" = 1
    )
GROUP BY 
    u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Id
ORDER BY 
    TotalPosts DESC, 
    TotalUpVotes DESC;