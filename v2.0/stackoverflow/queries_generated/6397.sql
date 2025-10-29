-- {"query": "6397.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 549} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxPostViews,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(p.CreationDate) AS LatestPost,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS TotalUpVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS TotalDownVotes,
    (
        SELECT STRING_AGG(t.TagName, ', ') 
        FROM Tags t 
        WHERE t.Id IN (
            SELECT TagId 
            FROM PostTags pt 
            WHERE pt.PostId = p.Id
        )
    ) AS PostTags,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 2
    ) AS SilverBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = u.Id AND b.Class = 3
    ) AS BronzeBadgeCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE 
    u.Reputation > 10000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    MAX(p.LastActivityDate) > DATEADD(month, -6, CURRENT_TIMESTAMP)
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;
