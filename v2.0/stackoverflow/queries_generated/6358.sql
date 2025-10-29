-- {"query": "6358.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 565} 

SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS TotalPositiveScorePosts,
    MAX(p.LastActivityDate) AS LastActivePost,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.ClosedDate ELSE NULL END) AS LastClosedQuestion,
    MIN(ph.CreationDate) AS FirstPostHistory,
    MAX(ph.CreationDate) AS LastPostHistory,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId ELSE NULL END) AS TotalDownVotes,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.UserId ELSE NULL END) AS TotalBadges,
    STRING_AGG(DISTINCT CASE WHEN t.TagName IS NOT NULL THEN t.TagName ELSE NULL END, ',') AS TaggedTopics
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
LEFT JOIN 
    (SELECT 
         pt.Id, 
         STRING_TO_ARRAY(SUBSTRING(pt.Tags, 2, LENGTH(pt.Tags)-2), ''><<') AS TagArray
     FROM 
         Posts pt 
     WHERE 
         pt.PostTypeId = 1) AS tg ON p.Id = tg.Id
LEFT JOIN 
    Tags t ON t.Id = ANY(tg.TagArray::INTEGER)
WHERE 
    u.Reputation > 100 
    AND u.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '6 months')
    AND p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    u.Reputation DESC, 
    TotalPositiveScorePosts DESC;
