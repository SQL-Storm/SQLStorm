SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
    MAX(p.Score) AS HighestScore,
    AVG(COALESCE(p.ViewCount, 0)) AS AvgViewCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesCast,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownvotesCast
FROM 
    Users AS u
LEFT JOIN 
    Posts AS p ON u.Id = p.OwnerUserId
WHERE 
    u.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.Id
ORDER BY 
    TotalPosts DESC, u.Reputation DESC
LIMIT 10;