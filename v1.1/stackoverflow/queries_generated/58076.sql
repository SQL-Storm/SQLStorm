-- {"query": "58076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 3532} 

SELECT u.Id, u.DisplayName, u.Reputation, 
       (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalPosts,
       (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS Questions,
       (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS Answers,
       (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
       (SELECT COUNT(*) FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 2) AS Upvotes,
       (SELECT COUNT(*) FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 3) AS Downvotes,
       (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
       (SELECT COUNT(*) FROM PostHistory ph INNER JOIN Posts p ON ph.PostId = p.Id WHERE ph.PostHistoryTypeId = 10 AND p.OwnerUserId = u.Id) AS ClosedPosts,
       (SELECT AVG(Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
       (SELECT SUM(ViewCount) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalViews
FROM Users u
WHERE (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) > 100
  AND (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) > 50
  AND (SELECT COUNT(*) FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 2) > 200
ORDER BY u.Reputation DESC, AvgPostScore DESC, TotalViews DESC
LIMIT 100;
