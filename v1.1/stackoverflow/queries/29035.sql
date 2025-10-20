SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScore,
    COALESCE(AVG(p.Score), 0) AS AverageScore,
    COALESCE(MAX(p.Score), 0) AS MaxScore,
    COALESCE(MIN(p.Score), 0) AS MinScore,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) AS QuestionWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) AS AnswerWithComments,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT CASE WHEN c.Score > 0 THEN c.Id END) AS PositiveComments,
    COUNT(DISTINCT CASE WHEN c.Score < 0 THEN c.Id END) AS NegativeComments,
    COALESCE(SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END), 0) AS PositiveCommentCount,
    COALESCE(SUM(CASE WHEN c.Score < 0 THEN 1 ELSE 0 END), 0) AS NegativeCommentCount,
    COUNT(DISTINCT b.Id) AS BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    COALESCE(COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END), 0) AS UpVotesGiven,
    COALESCE(COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END), 0) AS DownVotesGiven,
    COALESCE(COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END), 0) AS FavoritesGiven,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBountyAmount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBountyCloseAmount,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.Id END), 0) AS InitialTitles,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.Id END), 0) AS InitialBodies,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.Id END), 0) AS EditTitles,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id END), 0) AS EditBodies,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END), 0) AS PostClosed,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END), 0) AS PostReopened,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.Id END), 0) AS PostDeleted,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END), 0) AS PostUndeleted,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.Id END), 0) AS CommunityOwned,
    COALESCE(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN ph.Id END), 0) AS PostMigrated,
    COALESCE(COUNT(DISTINCT pl.Id), 0) AS PostLinks,
    COALESCE(COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END), 0) AS LinkedPosts,
    COALESCE(COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END), 0) AS DuplicatePosts,
    COALESCE(COUNT(DISTINCT CASE WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN p.Id END), 0) AS QuestionsWithTags,
    COALESCE(COUNT(DISTINCT CASE WHEN p.ViewCount > 0 THEN p.Id END), 0) AS ViewedPosts,
    COALESCE(SUM(CASE WHEN p.ViewCount > 0 THEN p.ViewCount ELSE 0 END), 0) AS TotalViews,
    COALESCE(COUNT(DISTINCT CASE WHEN p.LastActivityDate >= DATE '2023-01-01' THEN p.Id END), 0) AS RecentActivityPosts,
    COALESCE(COUNT(DISTINCT CASE WHEN p.LastActivityDate >= DATE '2023-01-01' AND p.PostTypeId = 1 THEN p.Id END), 0) AS RecentQuestions,
    COALESCE(COUNT(DISTINCT CASE WHEN p.LastActivityDate >= DATE '2023-01-01' AND p.PostTypeId = 2 THEN p.Id END), 0) AS RecentAnswers,
    COALESCE(COUNT(DISTINCT CASE WHEN p.CreationDate >= DATE '2023-01-01' THEN p.Id END), 0) AS NewPosts,
    COALESCE(COUNT(DISTINCT CASE WHEN p.CreationDate >= DATE '2023-01-01' AND p.PostTypeId = 1 THEN p.Id END), 0) AS NewQuestions,
    COALESCE(COUNT(DISTINCT CASE WHEN p.CreationDate >= DATE '2023-01-01' AND p.PostTypeId = 2 THEN p.Id END), 0) AS NewAnswers,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id), 2)
        ELSE 0 
    END AS AnswerPercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id), 2)
        ELSE 0 
    END AS QuestionWithAnswersPercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) * 100.0 / COUNT(DISTINCT p.Id), 2)
        ELSE 0 
    END AS AvgQuestionScorePercentage,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) * 100.0 / COUNT(DISTINCT p.Id), 2)
        ELSE 0 
    END AS AvgAnswerScorePercentage,
    COALESCE(STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN SPLIT_PART(p.Tags, '><', 1) END, ', '), 'No Tags') AS PopularTags,
    COALESCE(COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END), 0) AS PositiveScorePosts,
    COALESCE(COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END), 0) AS NegativeScorePosts,
    COALESCE(COUNT(DISTINCT CASE WHEN p.Score = 0 THEN p.Id END), 0) AS ZeroScorePosts,
    COALESCE(AVG(CASE WHEN p.Score > 0 THEN p.Score END), 0) AS AvgPositiveScore,
    COALESCE(AVG(CASE WHEN p.Score < 0 THEN p.Score END), 0) AS AvgNegativeScore,
    ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS RankByScore,
    RANK() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS RankByScoreWithTies,
    DENSE_RANK() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS DenseRankByScore
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId OR p.OwnerUserId IS NULL
LEFT JOIN Comments c ON u.Id = c.UserId OR c.UserId IS NULL
LEFT JOIN Badges b ON u.Id = b.UserId OR b.UserId IS NULL
LEFT JOIN Votes v ON u.Id = v.UserId OR v.UserId IS NULL
LEFT JOIN PostHistory ph ON u.Id = ph.UserId OR ph.UserId IS NULL
LEFT JOIN PostLinks pl ON u.Id = pl.PostId OR pl.PostId IS NULL
WHERE u.Id IN (SELECT Id FROM Users WHERE Reputation > 10000)
    AND (p.Id IS NULL OR p.CreationDate >= DATE '2020-01-01')
    AND (c.Id IS NULL OR c.CreationDate >= DATE '2020-01-01')
    AND (b.Id IS NULL OR b.Date >= DATE '2020-01-01')
    AND (v.Id IS NULL OR v.CreationDate >= DATE '2020-01-01')
    AND (ph.Id IS NULL OR ph.CreationDate >= DATE '2020-01-01')
    AND (pl.Id IS NULL OR pl.CreationDate >= DATE '2020-01-01')
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0)
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) > 0 OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) > 0)
ORDER BY SUM(COALESCE(p.Score, 0)) DESC, u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 100;