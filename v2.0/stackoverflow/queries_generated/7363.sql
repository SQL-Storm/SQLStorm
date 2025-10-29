-- {"query": "7363.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3460} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 10 THEN p.Id END) as HighScoreQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 5 THEN p.Id END) as HighScoreAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) as QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) as AnswersWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) as QuestionsWithFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) as CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN p.Id END) as AboveAverageQuestions,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) as TotalQuestionViews,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) as TotalAnswerViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) as LastQuestionDate,
    MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate END) as LastAnswerDate,
    MAX(p.CreationDate) as LastPostDate,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END) as QuestionsWithTags,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END) - 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Tags IS NULL THEN p.Tags END) as QuestionsWithNonEmptyTags,
    COUNT(DISTINCT b.Id) as BadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId IN (10, 11) 
               AND ph.UserId = u.Id) THEN p.Id END) as ModifiedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId IN (10, 11) 
               AND ph.UserId = u.Id) THEN p.Id END) as ModifiedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND 
        EXISTS(SELECT 1 FROM Comments c 
               WHERE c.PostId = p.Id 
               AND c.UserId = u.Id) THEN p.Id END) as CommentedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND 
        EXISTS(SELECT 1 FROM Comments c 
               WHERE c.PostId = p.Id 
               AND c.UserId = u.Id) THEN p.Id END) as CommentedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND 
        EXISTS(SELECT 1 FROM Votes v 
               WHERE v.PostId = p.Id 
               AND v.VoteTypeId IN (2,3) 
               AND v.UserId = u.Id) THEN p.Id END) as VotedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND 
        EXISTS(SELECT 1 FROM Votes v 
               WHERE v.PostId = p.Id 
               AND v.VoteTypeId IN (2,3) 
               AND v.UserId = u.Id) THEN p.Id END) as VotedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND 
        EXISTS(SELECT 1 FROM PostLinks pl 
               WHERE pl.PostId = p.Id 
               AND pl.LinkTypeId = 3) THEN p.Id END) as DuplicateQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND 
        EXISTS(SELECT 1 FROM PostLinks pl 
               WHERE pl.PostId = p.Id 
               AND pl.LinkTypeId = 3) THEN p.Id END) as DuplicateAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId = 25) THEN p.Id END) as TweetedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId = 25) THEN p.Id END) as TweetedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId IN (17,35,36)) THEN p.Id END) as MigratedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId IN (17,35,36)) THEN p.Id END) as MigratedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId IN (19,20)) THEN p.Id END) as ProtectedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND 
        EXISTS(SELECT 1 FROM PostHistory ph 
               WHERE ph.PostId = p.Id 
               AND ph.PostHistoryTypeId IN (19,20)) THEN p.Id END) as ProtectedAnswers,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b2 
         WHERE b2.UserId = u.Id 
         AND b2.Class = 1 
         AND b2.Date >= DATEADD(YEAR, -1, GETDATE())), 
        0
    ) as RecentGoldBadges,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b3 
         WHERE b3.UserId = u.Id 
         AND b3.Class = 2 
         AND b3.Date >= DATEADD(YEAR, -1, GETDATE())), 
        0
    ) as RecentSilverBadges,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b4 
         WHERE b4.UserId = u.Id 
         AND b4.Class = 3 
         AND b4.Date >= DATEADD(YEAR, -1, GETDATE())), 
        0
    ) as RecentBronzeBadges,
    CAST(
        (CASE WHEN u.Reputation > 10000 THEN 1 ELSE 0 END) +
        (CASE WHEN u.Reputation > 50000 THEN 1 ELSE 0 END) +
        (CASE WHEN u.Reputation > 100000 THEN 1 ELSE 0 END) +
        (CASE WHEN u.Reputation > 500000 THEN 1 ELSE 0 END) +
        (CASE WHEN u.Reputation > 1000000 THEN 1 ELSE 0 END) as TINYINT
    ) as ReputationTier,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as UserRankByPosts,
    ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) DESC) as UserRankByQuestionScore,
    ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) DESC) as UserRankByAnswerScore,
    AVG((SELECT COUNT(*) FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1)) OVER (PARTITION BY u.Id) as AvgQuestionsPerUser,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > (SELECT AVG(Count) FROM (SELECT COUNT(*) as Count FROM Posts GROUP BY OwnerUserId) as avg_counts) 
        THEN 'Above Average' 
        ELSE 'Below Average' 
    END as PostActivityLevel,
    CASE 
        WHEN u.Reputation > (SELECT AVG(Reputation) FROM Users) 
        THEN 'Above Average' 
        ELSE 'Below Average' 
    END as ReputationLevel,
    (SELECT TOP 1 p5.Title 
     FROM Posts p5 
     WHERE p5.OwnerUserId = u.Id 
     AND p5.PostTypeId = 1 
     ORDER BY p5.CreationDate DESC) as LatestQuestionTitle,
    (SELECT TOP 1 p6.Title 
     FROM Posts p6 
     WHERE p6.OwnerUserId = u.Id 
     AND p6.PostTypeId = 2 
     ORDER BY p6.CreationDate DESC) as LatestAnswerTitle,
    COALESCE(
        (SELECT COUNT(*) FROM PostHistory ph 
         WHERE ph.UserId = u.Id 
         AND ph.CreationDate >= DATEADD(YEAR, -1, GETDATE())), 
        0
    ) as RecentPostHistoryActions,
    (SELECT COUNT(*) FROM Votes v 
     WHERE v.UserId = u.Id 
     AND v.CreationDate >= DATEADD(YEAR, -1, GETDATE())) as RecentVotes,
    (SELECT COUNT(*) FROM Comments c 
     WHERE c.UserId = u.Id 
     AND c.CreationDate >= DATEADD(YEAR, -1, GETDATE())) as RecentComments,
    CASE WHEN COUNT(DISTINCT p.Id) > 1000 THEN 1 ELSE 0 END as HighPostVolume,
    CASE WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 100 THEN 1 ELSE 0 END as HighQuestionVolume,
    CASE WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 100 THEN 1 ELSE 0 END as HighAnswerVolume,
    CASE WHEN COUNT(DISTINCT b.Id) > 50 THEN 1 ELSE 0 END as HighBadgeVolume,
    CASE WHEN u.Reputation > 100000 THEN 1 ELSE 0 END as EliteReputation,
    DATEDIFF(DAY, u.CreationDate, GETDATE()) as AccountAgeInDays,
    ROUND(
        (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0)), 
        2
    ) as PercentageQuestions,
    ROUND(
        (COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0)), 
        2
    ) as PercentageAnswers,
    CASE 
        WHEN AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) > 20 THEN 'High Scoring Questions' 
        WHEN AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) > 5 THEN 'Medium Scoring Questions' 
        ELSE 'Low Scoring Questions' 
    END as QuestionScoreCategory,
    CASE 
        WHEN AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) > 10 THEN 'High Scoring Answers' 
        WHEN AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) > 2 THEN 'Medium Scoring Answers' 
        ELSE 'Low Scoring Answers' 
    END as AnswerScoreCategory,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT p7.Tags, ', ') 
         FROM Posts p7 
         WHERE p7.OwnerUserId = u.Id 
         AND p7.PostTypeId = 1 
         AND p7.Tags IS NOT NULL), 
        ''
    ) as AllUserTags,
    COALESCE(
        (SELECT COUNT(DISTINCT p8.PostId) 
         FROM PostLinks p8 
         WHERE p8.RelatedPostId IN (
             SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
         ) 
         AND p8.LinkTypeId = 1), 
        0
    ) as PostsLinkedToUserQuestions,
    (SELECT COUNT(*) FROM Posts p9 
     WHERE p9.OwnerUserId = u.Id 
     AND p9.FavoriteCount > 0) as QuestionsFavoritedByOthers,
    (SELECT COUNT(*) FROM Posts p10 
     WHERE p10.OwnerUserId = u.Id 
     AND p10.CommentCount > 5) as QuestionsWithManyComments,
    (SELECT COUNT(*) FROM Posts p11 
     WHERE p11.OwnerUserId = u.Id 
     AND p11.ViewCount > 10000) as HighlyViewedPosts,
    (SELECT AVG(p12.Score) FROM Posts p12 
     WHERE p12.OwnerUserId = u.Id) as AveragePostScore,
    (SELECT MAX(p13.ViewCount) FROM Posts p13 
     WHERE p13.OwnerUserId = u.Id) as MaxViewedPost,
    (SELECT MIN(p14.CreationDate) FROM Posts p14 
     WHERE p14.OwnerUserId = u.Id) as EarliestPostDate,
    (SELECT MAX(p15.CreationDate) FROM Posts p15 
     WHERE p15.OwnerUserId = u.Id) as LatestPostDate,
    (SELECT STRING_AGG(b5.Name, ', ') 
     FROM Badges b5 
     WHERE b5.UserId = u.Id 
     AND b5.Date >= DATEADD(YEAR, -1, GETDATE())) as RecentBadges,
    COALESCE(
        (SELECT COUNT(DISTINCT v2.Id) 
         FROM Votes v2 
         WHERE v2.PostId IN (
             SELECT Id FROM Posts WHERE OwnerUserId = u.Id
         )), 
        0
    ) as TotalVotesOnUserPosts,
    COALESCE(
        (SELECT COUNT(*) FROM PostHistory ph2 
         WHERE ph2.PostId IN (
             SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
         )), 
        0
    ) as QuestionHistoryEntries,
    COALESCE(
        (SELECT COUNT(*) FROM PostHistory ph3 
         WHERE ph3.PostId IN (
             SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2
         )), 
        0
    ) as AnswerHistoryEntries
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId 
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.AccountId IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.AccountId
HAVING COUNT(DISTINCT p.Id) > 10
ORDER BY TotalPosts DESC, u.Reputation DESC
OPTION (MAXDOP 4);