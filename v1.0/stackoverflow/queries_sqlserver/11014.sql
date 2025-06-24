
SELECT 
    pt.Name AS PostType,
    COUNT(p.Id) AS TotalPosts,
    AVG(v.voteCount) AS AvgVotesPerPost
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    (SELECT PostId, COUNT(Id) AS voteCount
     FROM Votes
     GROUP BY PostId) v ON p.Id = v.PostId
GROUP BY 
    pt.Name, v.voteCount
ORDER BY 
    TotalPosts DESC;
