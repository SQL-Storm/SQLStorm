-- {"query": "6598.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 438}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    AVG(p.ViewCount) AS AvgViewCount,
    MIN(p.LastActivityDate) AS FirstActivityDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    (
        SELECT COUNT(*) 
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Posts pl
        WHERE pl.ParentId = p.Id AND pl.PostTypeId = 2
    ) AS AnswerCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id, p.Score, p.ViewCount, p.LastActivityDate
HAVING 
    COUNT(DISTINCT v.PostId) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;