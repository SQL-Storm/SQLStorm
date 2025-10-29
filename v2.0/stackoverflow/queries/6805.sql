-- {"query": "6805.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 418}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.CreationDate) AS LatestAccountActivity,
    MAX(p.LastActivityDate) AS LatestPostActivity,
    AVG(p.Score) AS AvgPostScore,
    MAX(ph.CreationDate) AS LastEdit,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadges,
    (
        SELECT COUNT(*)
        FROM (
            SELECT DISTINCT pl.RelatedPostId
            FROM PostLinks pl
            WHERE pl.PostId = u.Id AND pl.LinkTypeId = 3
        ) AS dup
    ) AS DuplicateAnswersCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
WHERE 
    u.Reputation > 10000
    AND p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.CreationDate
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    u.Reputation DESC, TotalPosts DESC
LIMIT 100;