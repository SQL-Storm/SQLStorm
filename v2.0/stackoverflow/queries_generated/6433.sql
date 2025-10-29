-- {"query": "6433.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 561} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId ELSE NULL END) AS TotalDownVotes,
    COUNT(DISTINCT pl.RelatedPostId) AS TotalLinkedPosts,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId = 10 THEN bh.PostId ELSE NULL END) AS TotalClosedPosts,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViewCount,
    MIN(p.ViewCount) AS MinViewCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
    MAX(u.LastAccessDate) AS LastAccessDate,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate DESC) AS RecentActivityRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory bh ON p.Id = bh.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND (u.Location IS NOT NULL OR u.Location != '')
    AND (p.ViewCount > 100 OR p.ViewCount IS NULL)
    AND (v.VoteTypeId IN (2, 3) OR v.VoteTypeId IS NULL)
    AND (bh.PostHistoryTypeId IN (10) OR bh.PostHistoryTypeId IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    AvgScore DESC, 
    TotalUpVotes DESC;
