-- {"query": "10077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 554} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MIN(ph.CreationDate) AS FirstPostEdit,
    MAX(ph.CreationDate) AS LastPostEdit,
    AVG(p.Score) AS AvgScorePerPost,
    MAX(p.ViewCount) AS MaxViewsPerPost,
    MIN(p.ViewCount) AS MinViewsPerPost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
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
    ) AS BronzeBadgeCount,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id AND v.VoteTypeId = 8
    ) AS TotalBountyStarts
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 100
    AND p.LastActivityDate > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC
LIMIT 100;
