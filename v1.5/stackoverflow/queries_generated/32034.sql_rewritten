-- {"query": "32034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 314} 
SELECT 
    Users.Id AS UserId, 
    Users.DisplayName AS UserName, 
    Users.Reputation, 
    COUNT(DISTINCT Badges.Id) AS TotalBadges, 
    COUNT(DISTINCT Posts.Id) AS TotalPosts, 
    COUNT(DISTINCT Comments.Id) AS TotalComments, 
    COALESCE(SUM(Votes.BountyAmount), 0) AS TotalBountyEarned, 
    COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 1 THEN Posts.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 2 THEN Posts.Id END) AS AnswerCount,
    COUNT(DISTINCT CASE WHEN Votes.VoteTypeId = 2 THEN Votes.Id END) AS UpVotesCount,
    COUNT(DISTINCT CASE WHEN Votes.VoteTypeId = 3 THEN Votes.Id END) AS DownVotesCount
FROM 
    Users
LEFT JOIN 
    Badges ON Users.Id = Badges.UserId
LEFT JOIN 
    Posts ON Users.Id = Posts.OwnerUserId
LEFT JOIN 
    Comments ON Users.Id = Comments.UserId
LEFT JOIN 
    Votes ON Users.Id = Votes.UserId
WHERE 
    Users.Reputation > 1000
GROUP BY 
    Users.Id, Users.DisplayName, Users.Reputation
HAVING 
    COUNT(DISTINCT Posts.Id) > 10
ORDER BY 
    TotalBadges DESC, TotalBountyEarned DESC, TotalPosts DESC
LIMIT 10;