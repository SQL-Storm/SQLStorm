SELECT 
  u.DisplayName, 
  u.Reputation, 
  u.UpVotes, 
  u.DownVotes, 
  u.Views,
  COUNT(b.Id) AS TotalBadges,
  COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
  COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
  COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
  COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadges,
  COUNT(CASE WHEN b.TagBased = FALSE THEN 1 END) AS NamedBadges,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalPosts,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS TotalQuestions,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS TotalAnswers,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS TotalDownVotes
FROM Users u
LEFT JOIN Badges b ON u.Id = b.UserId
GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views
ORDER BY u.Reputation DESC
LIMIT 10;