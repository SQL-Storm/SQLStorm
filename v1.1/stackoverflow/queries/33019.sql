-- {"query": "33019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 357} 
SELECT 
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) AS PostsWithAcceptedAnswer,
    AVG(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN c.Score ELSE NULL END) AS AvgAcceptedAnswerScore,
    COUNT(DISTINCT u.Id) AS UniqueAuthors,
    AVG(u.Reputation) AS AvgAuthorReputation,
    COUNT(DISTINCT c.Id) AS TotalComments,
    AVG(c.Score) AS AvgCommentScore,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 11) AS UndeletionVotes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 10) AS DeletionVotes
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
LEFT JOIN 
    Votes v ON v.PostId = p.Id
WHERE 
    p.CreationDate >= '2021-01-01' AND p.CreationDate < '2022-01-01'
GROUP BY 
    p.PostTypeId, pt.Name
ORDER BY 
    TotalPosts DESC
LIMIT 10;