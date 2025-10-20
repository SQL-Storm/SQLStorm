-- {"query": "29035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 4142} 
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
    COALESCE(COUNT(DISTINCT CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN p.Id END), 0) AS QuestionsWithTags,
    COALESCE(COUNT(DISTINCT CASE WHEN p.ViewCount > 0 THEN p.Id END), 0) AS ViewedPosts,
    COALESCE(SUM(CASE WHEN p.ViewCount > 0 THEN p.ViewCount ELSE 0 END), 0) AS TotalViews,
    COALESCE(COUNT(DISTINCT CASE WHEN p.LastActivityDate >= '2023-01-01' THEN p.Id END), 0) AS RecentActivityPosts,
    COALESCE(COUNT(DISTINCT CASE WHEN p.LastActivityDate >= '2023-01-01' AND p.PostTypeId = 1 THEN p.Id END), 0) AS RecentQuestions,
    COALESCE(COUNT(DISTINCT CASE WHEN p.LastActivityDate >= '2023-01-01' AND p.PostTypeId = 2 THEN p.Id END), 0) AS RecentAnswers,
    COALESCE(COUNT(DISTINCT CASE WHEN p.CreationDate >= '2023-01-01' THEN p.Id END), 0) AS NewPosts,
    COALESCE(COUNT(DISTINCT CASE WHEN p.CreationDate >= '2023-01-01' AND p.PostTypeId = 1 THEN p.Id END), 0) AS NewQuestions,
    COALESCE(COUNT(DISTINCT CASE WHEN p.CreationDate >= '2023-01-01' AND p.PostTypeId = 2 THEN p.Id END), 0) AS NewAnswers,
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
    COALESCE(STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN SPLIT_PART(p.Tags, '><', 1) END, ', '), 'No Tags') AS PopularTags,
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
    AND (p.Id IS NULL OR p.CreationDate >= '2020-01-01')
    AND (c.Id IS NULL OR c.CreationDate >= '2020-01-01')
    AND (b.Id IS NULL OR b.Date >= '2020-01-01')
    AND (v.Id IS NULL OR v.CreationDate >= '2020-01-01')
    AND (ph.Id IS NULL OR ph.CreationDate >= '2020-01-01')
    AND (pl.Id IS NULL OR pl.CreationDate >= '2020-01-01')
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0)
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) > 0 OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) > 0)
ORDER BY SUM(COALESCE(p.Score, 0)) DESC, u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 100
EXCEPT
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS TotalPosts,
    0 AS Questions,
    0 AS Answers,
    0 AS TotalScore,
    0 AS QuestionScore,
    0 AS AnswerScore,
    0 AS AverageScore,
    0 AS MaxScore,
    0 AS MinScore,
    0 AS QuestionsWithAnswers,
    0 AS QuestionsWithAcceptedAnswer,
    0 AS ClosedQuestions,
    0 AS QuestionWithComments,
    0 AS AnswerWithComments,
    0 AS TotalComments,
    0 AS PositiveComments,
    0 AS NegativeComments,
    0 AS PositiveCommentCount,
    0 AS NegativeCommentCount,
    0 AS BadgesReceived,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    'NoBadges' AS BadgeNames,
    0 AS UpVotesGiven,
    0 AS DownVotesGiven,
    0 AS FavoritesGiven,
    0 AS TotalBountyAmount,
    0 AS TotalBountyCloseAmount,
    0 AS InitialTitles,
    0 AS InitialBodies,
    0 AS EditTitles,
    0 AS EditBodies,
    0 AS PostClosed,
    0 AS PostReopened,
    0 AS PostDeleted,
    0 AS PostUndeleted,
    0 AS CommunityOwned,
    0 AS PostMigrated,
    0 AS PostLinks,
    0 AS LinkedPosts,
    0 AS DuplicatePosts,
    0 AS QuestionsWithTags,
    0 AS ViewedPosts,
    0 AS TotalViews,
    0 AS RecentActivityPosts,
    0 AS RecentQuestions,
    0 AS RecentAnswers,
    0 AS NewPosts,
    0 AS NewQuestions,
    0 AS NewAnswers,
    0 AS AnswerPercentage,
    0 AS QuestionWithAnswersPercentage,
    0 AS AvgQuestionScorePercentage,
    0 AS AvgAnswerScorePercentage,
    'NoTags' AS PopularTags,
    0 AS PositiveScorePosts,
    0 AS NegativeScorePosts,
    0 AS ZeroScorePosts,
    0 AS AvgPositiveScore,
    0 AS AvgNegativeScore,
    0 AS RankByScore,
    0 AS RankByScoreWithTies,
    0 AS DenseRankByScore
FROM Users u
WHERE u.Id NOT IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT LastEditorUserId FROM Posts WHERE LastEditorUserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM Comments WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM Badges WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM Votes WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM PostHistory WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT PostId FROM PostLinks WHERE PostId IS NOT NULL)
    AND u.Reputation < 5000
    AND u.CreationDate < '2020-01-01'
    AND (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id OR LastEditorUserId = u.Id) = 0
    AND (SELECT COUNT(*) FROM Comments WHERE UserId = u.Id) = 0
    AND (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id) = 0
    AND (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id) = 0
    AND (SELECT COUNT(*) FROM PostHistory WHERE UserId = u.Id) = 0
    AND (SELECT COUNT(*) FROM PostLinks WHERE PostId = u.Id) = 0
    AND u.DisplayName IS NULL OR u.DisplayName = ''
    AND u.Location IS NULL OR u.Location = ''
    AND u.WebsiteUrl IS NULL OR u.WebsiteUrl = ''
    AND u.AboutMe IS NULL OR u.AboutMe = '' OR LENGTH(u.AboutMe) < 10
    AND u.Views IS NULL OR u.Views < 10
    AND u.UpVotes IS NULL OR u.UpVotes < 5
    AND u.DownVotes IS NULL OR u.DownVotes < 5
    AND u.ProfileImageUrl IS NULL OR u.ProfileImageUrl = ''
    AND u.EmailHash IS NULL OR u.EmailHash = ''
    AND u.AccountId IS NULL OR u.AccountId < 1
    AND u.Id NOT IN (SELECT DISTINCT Id FROM Users WHERE EXISTS (SELECT 1 FROM Posts WHERE Posts.OwnerUserId = Users.Id))
    AND u.Id NOT IN (SELECT DISTINCT Id FROM Users WHERE EXISTS (SELECT 1 FROM Comments WHERE Comments.UserId = Users.Id))
    AND u.Id NOT IN (SELECT DISTINCT Id FROM Users WHERE EXISTS (SELECT 1 FROM Badges WHERE Badges.UserId = Users.Id))
    AND u.Id NOT IN (SELECT DISTINCT Id FROM Users WHERE EXISTS (SELECT 1 FROM Votes WHERE Votes.UserId = Users.Id))
    AND u.Id NOT IN (SELECT DISTINCT Id FROM Users WHERE EXISTS (SELECT 1 FROM PostHistory WHERE PostHistory.UserId = Users.Id))
    AND u.Id NOT IN (SELECT DISTINCT Id FROM Users WHERE EXISTS (SELECT 1 FROM PostLinks WHERE PostLinks.PostId = Users.Id))
    AND u.Id NOT IN (SELECT DISTINCT ParentId FROM Posts WHERE ParentId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT LastEditorUserId FROM Posts WHERE LastEditorUserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM Comments WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM Badges WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM Votes WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT UserId FROM PostHistory WHERE UserId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT PostId FROM PostLinks WHERE PostId IS NOT NULL)
    AND u.Id NOT IN (SELECT DISTINCT RelatedPostId FROM PostLinks WHERE RelatedPostId IS NOT NULL)
    AND u.Id NOT IN (
        SELECT DISTINCT u.Id
        FROM Users u
        JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId 
        JOIN Comments c ON u.Id = c.UserId
        JOIN Badges b ON u.Id = b.UserId
        JOIN Votes v ON u.Id = v.UserId
        JOIN PostHistory ph ON u.Id = ph.UserId
        JOIN PostLinks pl ON u.Id = pl.PostId
        WHERE p.Id IS NOT NULL AND c.Id IS NOT NULL AND b.Id IS NOT NULL AND v.Id IS NOT NULL AND ph.Id IS NOT NULL AND pl.Id IS NOT NULL
    )
    AND ROW_NUMBER() OVER (ORDER BY u.Reputation ASC) <= 1000
    AND u.Id IN (
        SELECT u2.Id
        FROM Users u2
        JOIN Posts p2 ON u2.Id = p2.OwnerUserId
        WHERE p2.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
        GROUP BY u2.Id
        HAVING COUNT(DISTINCT p2.Id) > 50
    )
    AND u.Id IN (
        SELECT u3.Id
        FROM Users u3
        JOIN Posts p3 ON u3.Id = p3.OwnerUserId
        JOIN Comments c3 ON u3.Id = c3.UserId
        JOIN Badges b3 ON u3.Id = b3.UserId
        WHERE p3.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
        GROUP BY u3.Id, p3.OwnerUserId
        HAVING COUNT(DISTINCT c3.Id) > 100 AND COUNT(DISTINCT b3.Id) > 20
    )