-- {"query": "44100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 493}

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges,
    SUM(CASE WHEN b.TagBased = 0 THEN 1 ELSE 0 END) AS NamedBadges,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(CASE WHEN p.PostTypeId IN (4, 5) THEN 1 ELSE 0 END) AS TagWikiPosts,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.AnswerCount) AS TotalAnswers,
    SUM(p.CommentCount) AS TotalComments,
    SUM(p.FavoriteCount) AS TotalFavorites
FROM Users u
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalScore DESC
LIMIT 10;
