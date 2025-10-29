SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoined,
    STRING_AGG(DISTINCT b.Name, ', ') AS Badges,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS LastCloseReason,
    ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY ph.CreationDate DESC) AS LastEditRank
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN 
    PostHistory pht ON p.Id = pht.PostId AND pht.PostHistoryTypeId IN (33, 34)
LEFT JOIN 
    (SELECT PostId, COUNT(*) AS EditCount FROM PostHistory WHERE PostHistoryTypeId IN (4, 5, 6, 7) GROUP BY PostId) edits ON p.Id = edits.PostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Votes 
        WHERE VoteTypeId = 2 AND CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
    )
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    p.Tags,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    ph.Comment
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC;