-- {"query": "33093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 371} 
SELECT 
    p.PostTypeId, 
    pt.Name AS PostTypeName, 
    COUNT(p.Id) AS TotalPosts, 
    AVG(p.Score) AS AverageScore, 
    SUM(p.ViewCount) AS TotalViews, 
    COUNT(DISTINCT u.Id) AS UniqueAuthors, 
    MIN(p.CreationDate) AS EarliestPostDate, 
    MAX(p.LastActivityDate) AS MostRecentActivity, 
    COUNT(CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 1 END) AS QuestionsWithAnswers, 
    COUNT(CASE WHEN p.CommentCount > 10 THEN 1 END) AS PostsWithManyComments, 
    COALESCE(AVG(P.length), 0) AS AvgContentLength, 
    COUNT(DISTINCT v.PostId) AS VotedPosts, 
    COUNT(DISTINCT bv.UserId) AS TopVoters, 
    AVG(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS UpvoteDownvoteRatio 
FROM 
    Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT UserId FROM Votes WHERE VoteTypeId IN (2,3) GROUP BY UserId ORDER BY COUNT(*) DESC LIMIT 5
    ) bv ON v.UserId = bv.UserId
WHERE 
    p.CreationDate >= '2023-01-01' AND p.CreationDate < '2024-01-01'
GROUP BY 
    p.PostTypeId, pt.Name
ORDER BY 
    TotalPosts DESC
LIMIT 100;