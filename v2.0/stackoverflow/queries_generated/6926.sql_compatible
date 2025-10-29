SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
    COUNT(DISTINCT CASE WHEN vl.VoteTypeId = 2 THEN vl.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN vl.VoteTypeId = 3 THEN vl.UserId END) AS TotalDownVotes,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS FirstPostRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    Votes vl ON p.Id = vl.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON pl.RelatedPostId = t.Id
WHERE 
    p.PostTypeId IN (1, 2)
    AND u.Reputation > 100
    AND p.CreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') AND CAST('2024-10-01 12:34:56' AS timestamp)
GROUP BY 
    u.Id, u.DisplayName, p.PostTypeId, p.Score, ph.PostHistoryTypeId, ph.CreationDate, vl.VoteTypeId, vl.UserId, t.TagName, p.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 5
ORDER BY 
    TotalQuestionScore DESC, 
    TotalPosts DESC;