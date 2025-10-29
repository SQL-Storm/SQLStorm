SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreation,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS PopularPosts,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS TotalDuplicates,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN u.Id ELSE NULL END) AS TotalBadges,
    STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS PopularTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND (v.VoteTypeId = 2 OR v.VoteTypeId = 3)
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (
      SELECT p2.Id AS PostId, TRIM(tag_element) AS TagName
      FROM Posts p2,
           -- split tags string like '<tag1><tag2>' into array elements without angle brackets
           UNNEST(
             CASE
               WHEN COALESCE(p2.Tags, '') = '' THEN ARRAY[]::VARCHAR[]
               ELSE REGEXP_SPLIT_TO_ARRAY(REGEXP_REPLACE(COALESCE(p2.Tags, ''), '^<|>$', '', 'g'), '><')
             END
           ) AS tag_element
    ) t ON p.Id = t.PostId
WHERE 
    u.Reputation > 100
    AND p.CreationDate BETWEEN DATE_TRUNC('month', DATE '2024-10-01') AND DATE '2024-10-01'
GROUP BY 
    u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    TotalPosts DESC;