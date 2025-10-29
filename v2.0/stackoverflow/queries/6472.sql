-- {"query": "6472.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 443}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id ELSE NULL END) AS TotalClosedPosts,
    COUNT(DISTINCT CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN p.Id ELSE NULL END) AS TotalCommunityOwnedPosts,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MIN(p.CreationDate) AS FirstPostDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
    SUM(CASE WHEN EXISTS (
            SELECT 1
            FROM Votes v
            WHERE v.PostId = p.Id AND v.VoteTypeId = 2
        ) THEN 1 ELSE 0 END) AS TotalUpVotesPerPost,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS TotalGoldBadges,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS TotalDuplicateLinks
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC, TotalViews DESC
LIMIT 100;