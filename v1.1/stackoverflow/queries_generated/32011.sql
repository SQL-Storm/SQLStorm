-- {"query": "32011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 270} 

SELECT 
    Users.Id AS UserID, 
    Users.DisplayName, 
    MAX(Posts.ViewCount) AS MaxViews, 
    AVG(Posts.Score) AS AverageScore, 
    SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes, 
    COUNT(DISTINCT Comments.Id) AS CommentCount, 
    COUNT(DISTINCT PostLinks.RelatedPostId) AS RelatedPostsCount,
    COUNT(DISTINCT Tags.Id) AS DistinctTagsUsed
FROM 
    Users
JOIN 
    Posts ON Users.Id = Posts.OwnerUserId
LEFT JOIN 
    Votes ON Posts.Id = Votes.PostId
LEFT JOIN 
    Comments ON Posts.Id = Comments.PostId
LEFT JOIN 
    PostLinks ON Posts.Id = PostLinks.PostId
LEFT JOIN 
    Tags ON Posts.Tags LIKE '%' || Tags.TagName || '%'
WHERE 
    Users.CreationDate >= '2020-01-01' AND Posts.PostTypeId IN (1, 2)
GROUP BY 
    Users.Id, Users.DisplayName
HAVING 
    COUNT(DISTINCT PostLinks.RelatedPostId) > 5
ORDER BY 
    TotalUpvotes DESC, AverageScore DESC, MaxViews DESC
LIMIT 100;
