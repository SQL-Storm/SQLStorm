-- {"query": "6705.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 497}
SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS TotalUpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS TotalDownVotes,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActivePost,
    MIN(p.CreationDate) AS FirstPost,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedPost,
    STRING_AGG(DISTINCT t.TagName, ', ') AS MostCommonTags,
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
            WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
        ) AS dup
    ) AS DuplicateAnswers,
    (
        SELECT MAX(v2.BountyAmount) 
        FROM Votes v2
        WHERE v2.PostId = p.Id AND v2.VoteTypeId = 8
    ) AS MaxBounty
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    u.Reputation > 10000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, p.Id, p.PostTypeId, p.Score, p.LastActivityDate, p.CreationDate, ph.PostHistoryTypeId, ph.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, TotalPosts DESC;