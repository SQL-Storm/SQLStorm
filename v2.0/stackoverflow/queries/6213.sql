-- {"query": "6213.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 578}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 4 THEN p.Id ELSE NULL END) AS TotalTagWikiExcerpts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 5 THEN p.Id ELSE NULL END) AS TotalTagWikis,
    MAX(p.Score) AS HighestScoredPost,
    MIN(p.Score) AS LowestScoredPost,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.AnswerCount) AS TotalAnswersGiven,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    -- emulate GROUP_CONCAT ... SUBSTRING_INDEX by aggregating tags as comma-separated (may vary by dialect)
    STRING_AGG(DISTINCT p.Tags, ',' ORDER BY p.Tags) AS TopTags,
    MAX(ph.CreationDate) AS LastPostEdit,
    MAX(CASE WHEN pl.LinkTypeId = 3 THEN pl.CreationDate ELSE NULL END) AS LastDuplicateMarked,
    MAX(CASE WHEN b.Id IS NOT NULL THEN b.Date ELSE NULL END) AS LastBadgeEarned,
    ROW_NUMBER() OVER(PARTITION BY u.Id ORDER BY MAX(p.LastEditDate) DESC) AS MostRecentEdit,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS AcceptedAnswers
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 10000
    AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, TotalPosts DESC
LIMIT 100;