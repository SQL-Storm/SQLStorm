-- {"query": "52026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 403} 
SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, COUNT(DISTINCT p.Id) AS NumPosts, SUM(p.Score) AS TotalScore, AVG(p.Score) AS AvgScore, COUNT(DISTINCT c.Id) AS NumComments, COUNT(DISTINCT b.Id) AS NumBadges, COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS NumGoldBadges, COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS NumSilverBadges, COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS NumBronzeBadges, COUNT(DISTINCT pl.Id) AS NumPostLinks, COUNT(DISTINCT v.Id) AS NumVotes, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS NumUpvotesGiven, SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NumDownvotesGiven, MAX(p.CreationDate) AS LastPostDate, MIN(p.CreationDate) AS FirstPostDate
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
LEFT JOIN Votes v ON u.Id = v.UserId OR p.Id = v.PostId
WHERE u.Reputation > 1000 AND p.CreationDate > '2008-09-15 00:00:00'::timestamp
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
HAVING COUNT(DISTINCT p.Id) > 50
ORDER BY TotalScore DESC, NumPosts DESC, NumBadges DESC
LIMIT 500;