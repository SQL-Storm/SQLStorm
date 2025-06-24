-- Performance benchmarking query to analyze the most popular posts based on score and view count
SELECT 
    Posts.Id AS PostId,
    Posts.Title,
    Posts.CreationDate,
    Posts.Score,
    Posts.ViewCount,
    Users.DisplayName AS OwnerDisplayName,
    COUNT(Votes.Id) AS VoteCount,
    COUNT(Comments.Id) AS CommentCount,
    COALESCE(SUM(CASE WHEN Votes.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
    COALESCE(SUM(CASE WHEN Votes.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes
FROM 
    Posts
LEFT JOIN 
    Users ON Posts.OwnerUserId = Users.Id
LEFT JOIN 
    Votes ON Posts.Id = Votes.PostId
LEFT JOIN 
    Comments ON Posts.Id = Comments.PostId
WHERE 
    Posts.PostTypeId = 1 -- Only questions
GROUP BY 
    Posts.Id, Users.DisplayName
ORDER BY 
    Posts.Score DESC, Posts.ViewCount DESC
LIMIT 100; -- Limit results to top 100 posts
