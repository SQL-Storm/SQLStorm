-- {"query": "33086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 390} 
SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    AVG(EXTRACT(EPOCH FROM p.CreationDate - u.CreationDate)) / 86400 AS AvgAccountAgeDays,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(DISTINCT v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalUpDownVotes,
    COUNT(DISTINCT bl.RelatedPostId) AS LinkCount,
    COUNT(DISTINCT ph.Id) AS RevisionCount,
    COUNT(DISTINCT b.Id) AS BadgeCount
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostLinks bl ON bl.PostId = p.Id AND bl.LinkTypeId = 1
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (2,4,5,6,8,9,10,11,12,13,14,15,16,17,19,20,24,25,31,33,34,35,36,37,38,50,52,53,66)
LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY p.PostTypeId, pt.Name
ORDER BY TotalPosts DESC
LIMIT 100;