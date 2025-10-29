-- {"query": "6564.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 422} 
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN p.Id END) AS TotalTitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN p.Id END) AS TotalBodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN p.Id END) AS TotalCloseVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN p.Id END) AS TotalReOpenVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 4 THEN p.Id END) AS TotalTagEdits,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id END) AS TotalDownVotes,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestAccountCreation,
    AVG(p.AnswerCount) AS AvgAnswersPerQuestion,
    AVG(p.ViewCount) AS AvgViewsPerPost
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
    p.PostTypeId = 1
    AND b.Class IS NULL
    AND p.LastActivityDate > p.CreationDate
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalViews DESC;