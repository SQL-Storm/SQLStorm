-- {"query": "6867.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 467} 

SELECT 
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(ph.CreationDate) AS LatestPostHistoryActivity,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LatestPostClosedActivity,
    MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LatestPostReopenActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    MAX(v.BountyAmount) AS MaxBountyOffered,
    MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END) AS LatestUpvote,
    MAX(CASE WHEN v.VoteTypeId = 3 THEN v.CreationDate END) AS LatestDownvote,
    MAX(b.Date) AS LatestBadgeEarned,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 1000
    AND u.Id NOT IN (
        SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 3
    )
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 5
ORDER BY 
    u.Reputation DESC;
