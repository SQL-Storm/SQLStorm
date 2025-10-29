-- {"query": "7435.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3647} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as AnswerCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LatestPostDate,
        STRING_AGG(DISTINCT u.Location, ', ') as Locations,
        STRING_AGG(DISTINCT u.WebsiteUrl, ', ') as Websites,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.Score > 100) as HighScoringQuestions,
        (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2 AND p3.Score > 50) as HighScoringAnswers,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) as UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) as DownvoteCount,
        COALESCE((SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1 AND p4.AcceptedAnswerId IS NOT NULL), 0) as AcceptedAnswers,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                (COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) * 100.0 / COUNT(DISTINCT p.Id))
            ELSE 0 
        END as QuestionPercentage
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as UserRank,
        RANK() OVER (ORDER BY Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY AverageScore DESC) as AvgScoreRank,
        NTILE(10) OVER (ORDER BY Reputation) as ReputationDecile
    FROM (
        SELECT 
            us.*,
            AVG(us.Score) OVER (PARTITION BY us.UserId) as AverageScore,
            COUNT(*) OVER () as TotalUsers,
            MAX(us.Reputation) OVER () as MaxReputation
        FROM UserStats us
    ) ranked_data
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes' ELSE 'No' END as HasAcceptedAnswer,
        p.Tags,
        STRING_SPLIT(p.Tags, '<') as SplitTags,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.Score > 0) as PositiveAnswerCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11)) as ClosedReopenedCount,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        CASE 
            WHEN DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) < 30 THEN 'New'
            WHEN DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) BETWEEN 30 AND 365 THEN 'Medium'
            ELSE 'Old'
        END as QuestionAgeGroup,
        COALESCE((SELECT AVG(Score) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2), 0) as AvgAnswerScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) as FavoriteCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        p.Id as AnswerId,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        CASE WHEN p.Score > 10 THEN 'High' ELSE 'Low' END as ScoreCategory,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        COALESCE((SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId AND PostTypeId = 2), 0) as UserAvgAnswerScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as Downvotes
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as PostsWithTag,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreWithTag,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1) as QuestionsWithTag,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TopContributors
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
)
SELECT 
    'Performance Benchmark Result' as ReportTitle,
    COUNT(*) as TotalRecordsProcessed,
    (SELECT COUNT(*) FROM Users) as TotalUsers,
    (SELECT COUNT(*) FROM Posts) as TotalPosts,
    (SELECT COUNT(*) FROM Comments) as TotalComments,
    (SELECT COUNT(*) FROM Badges) as TotalBadges,
    (SELECT COUNT(*) FROM Tags) as TotalTags,
    (SELECT COUNT(*) FROM Votes) as TotalVotes,
    (SELECT COUNT(*) FROM PostHistory) as TotalPostHistory,
    (SELECT COUNT(*) FROM PostLinks) as TotalPostLinks,
    (SELECT AVG(Reputation) FROM Users) as AvgReputation,
    (SELECT AVG(Score) FROM Posts) as AvgPostScore,
    (SELECT AVG(ViewCount) FROM Posts) as AvgViewCount,
    (SELECT MAX(CreationDate) FROM Users) as NewestUserRegistration,
    (SELECT MIN(CreationDate) FROM Posts) as OldestPost,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Score > 100) as HighScoreQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Score > 50) as HighScoreAnswers,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 3) as BronzeBadges,
    (SELECT COUNT(DISTINCT PostId) FROM PostHistory WHERE PostHistoryTypeId = 10) as TotalClosedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostHistory WHERE PostHistoryTypeId = 11) as TotalReopenedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostHistory WHERE PostHistoryTypeId = 12) as TotalDeletedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostHistory WHERE PostHistoryTypeId = 13) as TotalUndeletedPosts,
    (SELECT COUNT(*) FROM Posts WHERE AcceptedAnswerId IS NOT NULL) as QuestionsWithAcceptedAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.AnswerCount > 0) as QuestionsWithAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Score > 0) as PositiveScoreAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.CommentCount > 0) as QuestionsWithComments,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.CommentCount > 0) as AnswersWithComments,
    (SELECT COUNT(*) FROM Tags WHERE IsRequired = 1) as RequiredTags,
    (SELECT COUNT(*) FROM Tags WHERE IsModeratorOnly = 1) as ModeratorOnlyTags,
    (SELECT COUNT(*) FROM Users WHERE Views > 1000) as PopularUsers,
    (SELECT COUNT(*) FROM Posts WHERE ViewCount > 1000) as PopularPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.ViewCount > 1000) as PopularQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.ViewCount > 500) as PopularAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Score < 0) as NegativeScoreQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Score < 0) as NegativeScoreAnswers,
    (SELECT COUNT(*) FROM Comments c WHERE LENGTH(c.Text) > 500) as LongComments,
    (SELECT COUNT(*) FROM Posts p WHERE LENGTH(p.Body) > 10000) as LongPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentPosts,
    (SELECT COUNT(*) FROM Users u WHERE u.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentUsers,
    (SELECT COUNT(*) FROM Votes v WHERE v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.Date > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentBadges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentPostHistory,
    (SELECT COUNT(*) FROM Comments c WHERE c.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentComments,
    (SELECT COUNT(*) FROM Posts p WHERE p.LastEditDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentlyEditedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.LastActivityDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as RecentlyActivePosts,
    (SELECT COUNT(DISTINCT OwnerUserId) FROM Posts WHERE CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days') as ActiveAuthorsInPeriod,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != '') as TaggedQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Tags IS NOT NULL AND p.Tags != '') as TaggedAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL) as ClosedQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.ClosedDate IS NOT NULL) as ClosedAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL) as CommunityOwnedQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.CommunityOwnedDate IS NOT NULL) as CommunityOwnedAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.AnswerCount > 10) as HighlyAnsweredQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.AnswerCount > 10) as HighlyAnsweredAnswers,
    (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1) as AvgAnswerCountPerQuestion,
    (SELECT MAX(AnswerCount) FROM Posts WHERE PostTypeId = 1) as MaxAnswerCount,
    (SELECT MIN(AnswerCount) FROM Posts WHERE PostTypeId = 1) as MinAnswerCount,
    (SELECT AVG(CommentCount) FROM Posts WHERE PostTypeId = 1) as AvgCommentCountPerQuestion,
    (SELECT AVG(CommentCount) FROM Posts WHERE PostTypeId = 2) as AvgCommentCountPerAnswer,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score > 10 AND p.ViewCount > 100) as HighScoreHighViewQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score < -5 AND p.ViewCount < 50) as LowScoreLowViewQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Title IS NOT NULL AND LENGTH(p.Title) > 100) as LongQuestionTitles,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Title IS NOT NULL AND LENGTH(p.Title) > 50) as LongAnswerTitles,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Body IS NOT NULL AND LENGTH(p.Body) > 5000) as LongQuestionBodies,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Body IS NOT NULL AND LENGTH(p.Body) > 1000) as LongAnswerBodies,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags LIKE '%<%<%') as MultipleTagQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.Tags IS NOT NULL AND p.Tags LIKE '%<%<%') as MultipleTagAnswers
FROM 
    (SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3) dummy_data
WHERE 
    EXISTS (SELECT 1 FROM Users u WHERE u.Reputation > 10000)
    AND EXISTS (SELECT 1 FROM Posts p WHERE p.PostTypeId = 1 AND p.Score > 100)
    AND EXISTS (SELECT 1 FROM Tags t WHERE t.TagName IS NOT NULL)
    AND EXISTS (SELECT 1 FROM Votes v WHERE v.VoteTypeId = 2)
    AND EXISTS (SELECT 1 FROM Comments c WHERE LENGTH(c.Text) > 100)
    AND EXISTS (SELECT 1 FROM Badges b WHERE b.Class = 1)
    AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostHistoryTypeId = 10)
    AND EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.LinkTypeId = 1)
    AND (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND Score > 5) > 1000
    AND (SELECT COUNT(*) FROM Users WHERE Reputation > 5000) > 500
    AND (SELECT COUNT(*) FROM Tags WHERE Count > 100) > 10
    AND (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND Score > 20) > 10000
    AND (SELECT COUNT(*) FROM Comments WHERE Score > 10 AND LENGTH(Text) > 500) > 100
    AND (SELECT COUNT(*) FROM Badges WHERE Date > CURRENT_TIMESTAMP - INTERVAL '1 year') > 10000
    AND (SELECT COUNT(*) FROM PostHistory WHERE CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year') > 50000
    AND (
        SELECT COUNT(*) FROM (
            SELECT u.Id 
            FROM Users u 
            JOIN Posts p ON u.Id = p.OwnerUserId 
            WHERE p.PostTypeId = 1 
            GROUP BY u.Id 
            HAVING COUNT(DISTINCT p.Id) > 100
        ) multiple_post_users 
    ) > 1000
    AND (
        SELECT AVG(Reputation) 
        FROM(
            SELECT u.Reputation 
            FROM Users u 
            JOIN Posts p ON u.Id = p.OwnerUserId 
            WHERE p.PostTypeId = 1 
            GROUP BY u.Id, u.Reputation 
            HAVING COUNT(DISTINCT p.Id) > 50
        ) avg_rep 
    ) > 10000
    AND (
        SELECT COUNT(*) 
        FROM Tags t 
        JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' 
        WHERE t.Count > 10
        GROUP BY t.TagName 
        HAVING COUNT(*) > 100
    ) > 50;