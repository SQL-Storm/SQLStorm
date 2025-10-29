-- {"query": "6001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 581} 
SELECT 
    u.DisplayName, 
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.CreationDate) AS FirstPostDate,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.CreationDate END) AS LastTitleEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.CreationDate END) AS LastBodyEdit,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS LastCloseReason,
    MAX(CASE WHEN ph.PostHistoryTypeId = 33 THEN ph.Comment END) AS LastPostNotice,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.PostId ELSE NULL END) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.PostId ELSE NULL END) AS TotalBountyPosts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS TotalDuplicatePosts,
    COUNT(DISTINCT CASE WHEN t.TagName LIKE 'SQL%' THEN t.Id ELSE NULL END) AS SQLTagsCount,
    b.Class AS BadgeClass,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 10000
    AND u.CreationDate < '2010-01-01'
    AND p.Score > 0
    AND p.ViewCount > 100
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Class, b.TagBased
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC, 
    TotalPosts DESC;