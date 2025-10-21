-- {"query": "33045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 270} 
SELECT
    u.DisplayName AS UserName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AverageScore,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COUNT(DISTINCT l.Id) AS LinkedPostsCount,
    COUNT(DISTINCT ph.Id) AS EditsMade
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostLinks l ON p.Id = l.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
WHERE
    u.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
    AND p.PostTypeId = 1 -- Questions only
GROUP BY u.DisplayName
ORDER BY TotalViews DESC
LIMIT 10;