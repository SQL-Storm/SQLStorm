-- {"query": "6278.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 484} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    MAX(ph.CreationDate) AS LatestPostHistoryEntry,
    AVG(p.Score) AS AvgPostScore,
    MAX(v.BountyAmount) AS MaxBountyOffered,
    (
        SELECT STRING_AGG(t.TagName, ', ')
        FROM Tags t
        WHERE t.Id IN (
            SELECT TagId
            FROM PostTags pt
            WHERE pt.PostId = p.Id
        )
    ) AS MostFrequentTags,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 1
    ) AS AcceptedAnswerCount,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS DuplicateQuestionsCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 1000
AND 
    p.LastActivityDate > DATEADD(month, -12, GETDATE())
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;
