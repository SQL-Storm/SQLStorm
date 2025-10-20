SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT b.Id) AS BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
    MAX(p.CreationDate) AS LatestPostDate,
    MIN(p.CreationDate) AS FirstPostDate,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS Favorites,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END) AS DistinctTagUsage,
    STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL THEN SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)) END, ', ') AS AllTagsUsed,
    COUNT(DISTINCT pl.Id) AS PostLinks,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) AS DuplicateLinks,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END) AS RegularLinks,
    COUNT(DISTINCT u2.Id) AS UsersTheyFollow,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS TotalQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) AS QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) AS AnswersWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) AS QuestionsWithFavorites,
    MAX(CASE WHEN u.LastAccessDate > u.CreationDate THEN EXTRACT(DAY FROM (u.LastAccessDate - u.CreationDate)) ELSE 0 END) AS DaysSinceRegistration,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) AS CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score >= 10 THEN p.Id END) AS HighScoringQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score >= 10 THEN p.Id END) AS HighScoringAnswers,
    COUNT(DISTINCT CASE WHEN b.Name IN (SELECT Name FROM Badges GROUP BY Name HAVING COUNT(*) > 100) THEN b.Id END) AS PopularBadgesReceived
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
LEFT JOIN Users u2 ON u.Id = u2.AccountId
WHERE u.Id BETWEEN 1 AND 10000
  AND u.CreationDate >= '2010-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate, u.CreationDate
HAVING COUNT(DISTINCT p.Id) > 0
   AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 5
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 1000;