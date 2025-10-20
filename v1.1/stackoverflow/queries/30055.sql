SELECT Users.Id AS UserId,
       Users.DisplayName AS UserDisplayName,
       Users.Reputation,
       SUM(Votes.VoteTypeId) AS TotalVotes,
       COUNT(DISTINCT Posts.Id) AS TotalPosts
FROM Users
LEFT JOIN Votes ON Users.Id = Votes.UserId
LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
GROUP BY Users.Id, Users.DisplayName, Users.Reputation
ORDER BY TotalVotes DESC, TotalPosts DESC, Users.Reputation DESC
LIMIT 100;