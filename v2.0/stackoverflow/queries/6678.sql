-- {"query": "6678.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 429}
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalDownVotes,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActivity,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS RecencyRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND (
        u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
        OR u.LastAccessDate IS NULL
    )
    AND (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
    ) > 0
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AvgScore DESC, 
    TotalPosts DESC
LIMIT 100;