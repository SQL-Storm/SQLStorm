SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    SUM(CASE WHEN COALESCE(b.TagBased, FALSE) = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
    SUM(CASE WHEN COALESCE(b.TagBased, FALSE) = FALSE THEN 1 ELSE 0 END) AS NamedBadges,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN p.PostTypeId = 3 THEN 1 ELSE 0 END) AS TotalWikis,
    SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
    SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswerCount,
    SUM(COALESCE(p.CommentCount, 0)) AS TotalComments,
    SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavorites,
    COUNT(v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoriteVotes
FROM
    Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
ORDER BY
    u.Reputation DESC
LIMIT 100;