-- {"query": "7973.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 4311} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.AccountId,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.AccountId, u.CreationDate
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as ReputationRank,
        PERCENT_RANK() OVER (ORDER BY Reputation) as ReputationPercentile,
        NTILE(100) OVER (ORDER BY Reputation) as ReputationDecile,
        DENSE_RANK() OVER (ORDER BY PostCount DESC) as PostCountRank
    FROM UserStats
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as ModerationCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (5, 6, 24) THEN ph.Id END) as EditCount,
        MAX(ph.CreationDate) as LastActivityDate,
        STRING_AGG(DISTINCT pot.Name, ', ') as ActivityTypes,
        COUNT(DISTINCT ph.PostId) as AffectedPosts,
        AVG(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 ELSE 0 END) as ModerationRatio
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN PostHistoryTypes pot ON ph.PostHistoryTypeId = pot.Id
    GROUP BY u.Id, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COUNT(DISTINCT p.Id) as AssociatedPosts,
        AVG(p.Score) as AvgPostScore,
        AVG(CAST(LEN(p.Body) AS FLOAT)) as AvgBodyLength,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TopContributors,
        MAX(p.CreationDate) as LastPostDate
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'Unanswered'
        END as QuestionStatus,
        CASE 
            WHEN p.ViewCount >= 1000 THEN 'HighTraffic'
            WHEN p.ViewCount >= 100 THEN 'MediumTraffic'
            WHEN p.ViewCount >= 10 THEN 'LowTraffic'
            ELSE 'VeryLowTraffic'
        END as TrafficLevel,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        DATEDIFF(day, p.CreationDate, GETDATE()) as PostAgeDays,
        CASE 
            WHEN DATEDIFF(day, p.CreationDate, GETDATE()) <= 7 THEN 'New'
            WHEN DATEDIFF(day, p.CreationDate, GETDATE()) <= 30 THEN 'Recent'
            WHEN DATEDIFF(day, p.CreationDate, GETDATE()) <= 365 THEN 'Old'
            ELSE 'VeryOld'
        END as AgeCategory,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyUpvoted'
            WHEN p.Score > 25 THEN 'Upvoted'
            WHEN p.Score > 0 THEN 'Neutral'
            WHEN p.Score < 0 THEN 'Downvoted'
            ELSE 'NoVotes'
        END as VoteStatus,
        CASE 
            WHEN p.Tags IS NOT NULL AND LEN(p.Tags) > 0 THEN 
                STRING_SPLIT(p.Tags, '><')
            ELSE NULL
        END as TagTokens
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    GETDATE() as ReportGenerated,
    COUNT(*) as TotalUsers,
    (SELECT COUNT(*) FROM Posts) as TotalPosts,
    (SELECT COUNT(*) FROM Tags) as TotalTags,
    (SELECT COUNT(*) FROM PostHistory) as TotalHistory,
    (SELECT COUNT(*) FROM Comments) as TotalComments,
    (SELECT COUNT(*) FROM Badges) as TotalBadges,
    (SELECT COUNT(DISTINCT AccountId) FROM Users WHERE AccountId IS NOT NULL) as DistinctAccounts,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId IN (1, 2)) as QuestionAnswerPosts,
    (SELECT AVG(Reputation) FROM UserStats) as AvgReputation,
    (SELECT MIN(Reputation) FROM UserStats) as MinReputation,
    (SELECT MAX(Reputation) FROM UserStats) as MaxReputation,
    (SELECT AVG(PostCount) FROM UserStats) as AvgPostsPerUser,
    (SELECT AVG(BadgeCount) FROM UserStats) as AvgBadgesPerUser,
    (SELECT AVG(QuestionCount) FROM UserStats) as AvgQuestionsPerUser,
    (SELECT AVG(AnswerCount) FROM UserStats) as AvgAnswersPerUser,
    COUNT(DISTINCT CASE WHEN ps.Reputation > 10000 THEN ps.UserId END) as HighReputationUsers,
    COUNT(DISTINCT CASE WHEN ps.PostCount > 1000 THEN ps.UserId END) as ActiveUsers,
    COUNT(DISTINCT CASE WHEN pa.QuestionStatus = 'Answered' THEN pa.PostId END) as AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN pa.QuestionStatus = 'Unanswered' THEN pa.PostId END) as UnansweredQuestions,
    COUNT(DISTINCT CASE WHEN pa.TrafficLevel = 'HighTraffic' THEN pa.PostId END) as HighTrafficPosts,
    COUNT(DISTINCT CASE WHEN pa.AgeCategory = 'New' THEN pa.PostId END) as NewPosts,
    COUNT(DISTINCT CASE WHEN pa.AgeCategory = 'Recent' THEN pa.PostId END) as RecentPosts,
    COUNT(DISTINCT CASE WHEN pa.VoteStatus = 'HighlyUpvoted' THEN pa.PostId END) as HighlyUpvotedPosts,
    COUNT(DISTINCT CASE WHEN EXISTS (
        SELECT 1 FROM PostLinks pl 
        WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 3
    ) THEN pa.PostId END) as DuplicatePosts,
    COUNT(DISTINCT CASE WHEN EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.PostId = pa.PostId AND v.VoteTypeId IN (2,3)
    ) THEN pa.PostId END) as VotedPosts,
    (SELECT COUNT(*) FROM (
        SELECT p.Id 
        FROM Posts p 
        WHERE p.Score > 100 
        AND p.PostTypeId = 1
        AND EXISTS(
            SELECT 1 FROM Posts pa 
            WHERE pa.ParentId = p.Id 
            AND pa.Score > 50
        )
        AND EXISTS(
            SELECT 1 FROM Votes v 
            WHERE v.PostId = p.Id 
            AND v.VoteTypeId = 7
        )
    ) x) as HighScoreQuestionsWithAnswerAndReopen,
    (SELECT AVG(LEN(p.Body)) FROM Posts p WHERE p.Body IS NOT NULL) as AvgPostBodyLength,
    (SELECT MAX(LEN(p.Body)) FROM Posts p WHERE p.Body IS NOT NULL) as MaxPostBodyLength,
    (SELECT MIN(LEN(p.Body)) FROM Posts p WHERE p.Body IS NOT NULL) as MinPostBodyLength,
    (SELECT COUNT(*) FROM (
        SELECT OwnerUserId 
        FROM Posts p 
        WHERE p.PostTypeId = 1 
        GROUP BY OwnerUserId 
        HAVING COUNT(*) >= 100
    ) x) as TopQuestionAuthors,
    (SELECT COUNT(*) FROM (
        SELECT OwnerUserId 
        FROM Posts p 
        WHERE p.PostTypeId = 2 
        GROUP BY OwnerUserId 
        HAVING COUNT(*) >= 100
    ) x) as TopAnswerAuthors,
    CONCAT(
        'Users in top 10% by reputation: ', 
        (SELECT COUNT(*) FROM RankedUsers WHERE ReputationPercentile >= 0.9)
    ) as Top10PercentUsers,
    CONCAT(
        'Users in top 10% by post count: ', 
        (SELECT COUNT(*) FROM RankedUsers WHERE PostCountRank <= (SELECT COUNT(*) FROM UserStats) * 0.1)
    ) as Top10PercentPostUsers,
    (SELECT COUNT(*) FROM (
        SELECT u.Id, COUNT(DISTINCT ph.Id) as HistoryCount
        FROM Users u
        LEFT JOIN PostHistory ph ON u.Id = ph.UserId
        GROUP BY u.Id
        HAVING COUNT(DISTINCT ph.Id) >= 1000
    ) x) as ActiveHistoryUsers,
    (SELECT COUNT(*) FROM (
        SELECT t.TagName
        FROM Tags t
        WHERE t.Count >= 1000
    ) x) as PopularTags,
    (SELECT COUNT(*) FROM (
        SELECT t.TagName
        FROM Tags t
        WHERE t.Count >= 100 AND t.Count < 1000
    ) x) as MediumTags,
    (SELECT COUNT(*) FROM (
        SELECT t.TagName
        FROM Tags t
        WHERE t.Count < 100
    ) x) as LessPopularTags,
    (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1) as AvgAnswersPerQuestion,
    (SELECT AVG(CommentCount) FROM Posts WHERE PostTypeId = 1) as AvgCommentsPerQuestion,
    (SELECT COUNT(*) FROM (
        SELECT p.Id
        FROM Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
        WHERE p.PostTypeId = 1
        AND p.Score >= 50
        AND u.Reputation >= 10000
        AND p.CreationDate >= DATEADD(month, -6, GETDATE())
    ) x) as RecentHighRepQuestions,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 2 AND p.Score > 0) as AvgPositiveAnswerScore,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 1 AND p.Score > 0) as AvgPositiveQuestionScore,
    (SELECT MAX(p.ViewCount) FROM Posts p WHERE p.PostTypeId = 1) as MaxQuestionViews,
    (SELECT MAX(p.ViewCount) FROM Posts p WHERE p.PostTypeId = 2) as MaxAnswerViews,
    (SELECT COUNT(*) FROM (
        SELECT p.Id
        FROM Posts p
        INNER JOIN Users u ON p.OwnerUserId = u.Id
        WHERE p.PostTypeId = 1
        AND u.Reputation < 100
        AND p.CreationDate >= DATEADD(year, -1, GETDATE())
        AND p.Score < 0
    ) x) as RecentNegativeScoreQuestions,
    (SELECT COUNT(*) FROM (
        SELECT p.Id
        FROM Posts p
        JOIN Posts pa ON p.Id = pa.ParentId
        WHERE p.PostTypeId = 1
        AND pa.Score > 20
        AND pa.CreationDate >= DATEADD(month, -3, GETDATE())
    ) x) as RecentHighScoreAnswers,
    (SELECT COUNT(*) FROM (
        SELECT u.Id
        FROM Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Comments c ON u.Id = c.UserId
        LEFT JOIN Badges b ON u.Id = b.UserId
        WHERE p.Id IS NOT NULL OR c.Id IS NOT NULL OR b.Id IS NOT NULL
        GROUP BY u.Id
        HAVING COUNT(p.Id) + COUNT(c.Id) + COUNT(b.Id) >= 100
    ) x) as HighlyActiveUsers,
    (SELECT COUNT(*) FROM (
        SELECT p.Id
        FROM Posts p
        WHERE p.CreationDate >= DATEADD(day, -7, GETDATE())
        AND p.Score > 100
        AND p.PostTypeId = 1
    ) x) as RecentHighScoreQuestions,
    (SELECT COUNT(*) FROM (
        SELECT p.Id
        FROM Posts p
        LEFT JOIN PostLinks pl ON p.Id = pl.PostId
        WHERE p.PostTypeId = 1
        AND pl.Id IS NOT NULL
        AND p.CreationDate >= DATEADD(month, -1, GETDATE())
    ) x) as RecentlyLinkedQuestions,
    (SELECT COUNT(*) FROM (
        SELECT p.Id
        FROM Posts p
        WHERE p.CreationDate >= DATEADD(day, -30, GETDATE())
        AND p.PostTypeId = 2
        AND p.Score > 10
        AND EXISTS (
            SELECT 1 FROM PostLinks pl 
            WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
        )
    ) x) as RecentHighScoreAnswersWithLinks,
    (SELECT COUNT(DISTINCT u.Id)
    FROM Users u
    INNER JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 24)
    AND ph.CreationDate >= DATEADD(day, -30, GETDATE())) as RecentActiveEditUsers,
    (SELECT COUNT(DISTINCT u.Id)
    FROM Users u
    INNER JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
    AND ph.CreationDate >= DATEADD(day, -30, GETDATE())) as RecentModerationUsers,
    (SELECT COUNT(DISTINCT u.Id)
    FROM Users u
    INNER JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId = 24
    AND ph.CreationDate >= DATEADD(day, -30, GETDATE())) as RecentEditUsers,
    (SELECT COUNT(DISTINCT p.Id)
    FROM Posts p
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= DATEADD(day, -7, GETDATE())
    AND p.Score > 50
    AND EXISTS(
        SELECT 1 FROM PostLinks pl 
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    )) as RecentDuplicateQuestions,
    (SELECT COUNT(DISTINCT p.Id)
    FROM Posts p
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= DATEADD(day, -14, GETDATE())
    AND p.Score > 25
    AND p.AnswerCount > 0
    AND p.CommentCount > 5) as HighlyEngagedQuestions
FROM UserStats ps
JOIN UserActivity ua ON ps.UserId = ua.UserId
JOIN PostAnalysis pa ON ps.UserId = pa.OwnerUserId
JOIN TagAnalysis ta ON ta.TagName LIKE '%sql%'
WHERE ps.Reputation >= 100
AND ps.PostCount >= 10
GROUP BY ps.UserId, ps.Reputation, ps.PostCount, ps.CommentCount, ps.BadgeCount, ps.QuestionCount, ps.AnswerCount, ps.TotalQuestionScore, ps.TotalAnswerScore, ps.AvgQuestionScore, ps.AvgAnswerScore, ps.LastPostDate, ps.AccountAgeDays, ps.ReputationRank, ps.ReputationPercentile, ps.ReputationDecile, ps.PostCountRank, ua.HistoryCount, ua.ModerationCount, ua.EditCount, ua.LastActivityDate, ua.ActivityTypes, ua.AffectedPosts, ua.ModerationRatio, ta.TagName, ta.TagCount, ta.ExcerptPostId, ta.WikiPostId, ta.AssociatedPosts, ta.AvgPostScore, ta.AvgBodyLength, ta.TopContributors, ta.LastPostDate, pa.PostId, pa.Title, pa.Score, pa.ViewCount, pa.CommentCount, pa.CreationDate, pa.OwnerUserId, pa.OwnerName, pa.PostTypeId, pa.PostTypeName, pa.Tags, pa.PostCategory, pa.QuestionStatus, pa.TrafficLevel, pa.AnswerCount, pa.FavoriteCount, pa.PostAgeDays, pa.AgeCategory, pa.VoteStatus, pa.TagTokens
HAVING COUNT(*) > 0
UNION ALL
SELECT 
    'Secondary Performance Report' as ReportTitle,
    GETDATE() as ReportGenerated,
    NULL as TotalUsers,
    NULL as TotalPosts,
    NULL as TotalTags,
    NULL as TotalHistory,
    NULL as TotalComments,
    NULL as TotalBadges,
    NULL as DistinctAccounts,
    NULL as QuestionAnswerPosts,
    NULL as AvgReputation,
    NULL as MinReputation,
    NULL as MaxReputation,
    NULL as AvgPostsPerUser,
    NULL as AvgBadgesPerUser,
    NULL as AvgQuestionsPerUser,
    NULL as AvgAnswersPerUser,
    NULL as HighReputationUsers,
    NULL as ActiveUsers,
    NULL as AnsweredQuestions,
    NULL as UnansweredQuestions,
    NULL as HighTrafficPosts,
    NULL as NewPosts,
    NULL as RecentPosts,
    NULL as HighlyUpvotedPosts,
    NULL as DuplicatePosts,
    NULL as VotedPosts,
    NULL as HighScoreQuestionsWithAnswerAndReopen,
    NULL as AvgPostBodyLength,
    NULL as MaxPostBodyLength,
    NULL as MinPostBodyLength,
    NULL as TopQuestionAuthors,
    NULL as TopAnswerAuthors,
    NULL as Top10PercentUsers,
    NULL as Top10PercentPostUsers,
    NULL as ActiveHistoryUsers,
    NULL as PopularTags,
    NULL as MediumTags,
    NULL as LessPopularTags,
    NULL as AvgAnswersPerQuestion,
    NULL as AvgCommentsPerQuestion,
    NULL as RecentHighRepQuestions,
    NULL as AvgPositiveAnswerScore,
    NULL as AvgPositiveQuestionScore,
    NULL as MaxQuestionViews,
    NULL as MaxAnswerViews,
    NULL as RecentNegativeScoreQuestions,
    NULL as RecentHighScoreAnswers,
    NULL as HighlyActiveUsers,
    NULL as RecentHighScoreQuestions,
    NULL as RecentlyLinkedQuestions,
    NULL as RecentHighScoreAnswersWithLinks,
    NULL as RecentActiveEditUsers,
    NULL as RecentModerationUsers,
    NULL as RecentEditUsers,
    NULL as RecentDuplicateQuestions,
    NULL as HighlyEngagedQuestions
FROM DualTable
WHERE 1 = 0;