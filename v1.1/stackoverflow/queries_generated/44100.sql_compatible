SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
    SUM(CASE WHEN b.TagBased = FALSE THEN 1 ELSE 0 END) AS NamedBadges,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(CASE WHEN p.PostTypeId IN (4, 5) THEN 1 ELSE 0 END) AS TagWikiPosts,
    SUM(COALESCE(p.Score, 0)) AS TotalScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswers,
    SUM(COALESCE(p.CommentCount, 0)) AS TotalComments,
    SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavorites
FROM Users u
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalScore DESC
LIMIT 10;