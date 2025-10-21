-- {"query": "32046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 237} 
SELECT 
    Users.DisplayName,
    Users.Reputation,
    Users.CreationDate,
    Users.LastAccessDate,
    Users.Location,
    COALESCE(MAX(Posts.Score), 0) AS MaxPostScore,
    AVG(CAST(Posts.Score AS float)) AS AvgPostScore,
    COUNT(DISTINCT Posts.Id) AS TotalPosts,
    COUNT(DISTINCT Comments.Id) AS TotalComments,
    COUNT(DISTINCT Votes.Id) AS TotalVotes,
    COUNT(DISTINCT Badges.Id) AS TotalBadges
FROM 
    Users
LEFT JOIN 
    Posts ON Users.Id = Posts.OwnerUserId
LEFT JOIN 
    Comments ON Users.Id = Comments.UserId
LEFT JOIN 
    Votes ON Users.Id = Votes.UserId
LEFT JOIN 
    Badges ON Users.Id = Badges.UserId
WHERE 
    Users.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 YEAR')
GROUP BY 
    Users.Id, Users.DisplayName, Users.Reputation, Users.CreationDate, Users.LastAccessDate, Users.Location
ORDER BY 
    Users.Reputation DESC, AvgPostScore DESC;