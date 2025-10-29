-- {"query": "6876.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 499}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS TotalAnswersToQuestions,
    SUM(v.BountyAmount) AS TotalBountyAmount,
    MAX(u.LastAccessDate) AS LastAccessDate,
    MIN(p.CreationDate) AS EarliestPost,
    MAX(ph.CreationDate) AS LatestPostEdit,
    b.Name AS LatestBadge,
    b.Date AS LatestBadgeDate,
    t.TagName AS MostUsedTag,
    t.Count AS MostUsedTagCount
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
LEFT JOIN 
    Tags t ON t.ExcerptPostId = p.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
LEFT JOIN 
    (SELECT UserId, MAX(Date) AS MaxDate
     FROM Badges
     GROUP BY UserId) bb ON u.Id = bb.UserId
WHERE 
    u.Reputation > 10000
AND 
    u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR)
AND 
    p.ViewCount > 100
AND 
    p.Score > 0
AND 
    t.Count > 100
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.Name, b.Date, t.TagName, t.Count
ORDER BY 
    TotalPosts DESC, TotalScore DESC
LIMIT 100;