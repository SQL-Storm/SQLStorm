SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    MAX(b.Date) AS LastBadgeEarned,
    MAX(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Score END) AS HighestAcceptedAnswerScore,
    STRING_AGG(DISTINCT t.TagName, ', ') AS PopularTags,
    STRING_AGG(dup.Title, ', ' ORDER BY dup.MaxCreationDate DESC) AS Duplicates
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
LEFT JOIN (
    SELECT pl_inner.PostId,
           p_inner.Title,
           MAX(pl_inner.CreationDate) AS MaxCreationDate
    FROM PostLinks pl_inner
    JOIN Posts p_inner ON p_inner.Id = pl_inner.PostId
    WHERE pl_inner.LinkTypeId = 3
    GROUP BY pl_inner.PostId, p_inner.Title
) dup ON dup.PostId = p.Id
WHERE 
    u.Reputation > 1000
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    TotalPosts DESC, TotalVotes DESC
LIMIT 100;