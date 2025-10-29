-- {"query": "7976.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3531} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostRankings AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as AuthorName,
        p.PostTypeId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as OverallScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        LAG(p.Title, 1) OVER (ORDER BY p.CreationDate) as PreviousPostTitle,
        LEAD(p.Title, 1) OVER (ORDER BY p.CreationDate) as NextPostTitle
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
ComplexTagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Highly Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel,
        STRING_AGG(
            CASE 
                WHEN CHARINDEX('>', t.Tags) > 0 THEN SUBSTRING(t.Tags, 2, CHARINDEX('>', t.Tags) - 2)
                ELSE t.Tags
            END, ', '
        ) as TagExtract,
        (
            SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.Tags LIKE '%' + t.TagName + '%' 
            AND p.PostTypeId = 1
        ) as RelatedQuestions,
        (
            SELECT AVG(p.Score) 
            FROM Posts p 
            WHERE p.Tags LIKE '%' + t.TagName + '%' 
            AND p.PostTypeId = 1
        ) as AvgQuestionScore
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.Tags
),
UserPostTrends AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(p.Id) as MonthlyPosts,
        DATE_TRUNC('month', p.CreationDate) as PostMonth,
        SUM(p.Score) as MonthlyScore,
        SUM(p.ViewCount) as MonthlyViews,
        AVG(p.Score) as AvgMonthlyScore,
        (
            SELECT COUNT(*) 
            FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            AND p2.CreationDate BETWEEN DATEADD(month, -1, p.CreationDate) AND p.CreationDate
        ) as PrevMonthPosts,
        LAG(COUNT(p.Id), 1, 0) OVER (PARTITION BY u.Id ORDER BY DATE_TRUNC('month', p.CreationDate)) as PrevMonthPostsLag,
        CASE 
            WHEN COUNT(p.Id) > LAG(COUNT(p.Id), 1, 0) OVER (PARTITION BY u.Id ORDER BY DATE_TRUNC('month', p.CreationDate)) 
            THEN 'Growth'
            WHEN COUNT(p.Id) < LAG(COUNT(p.Id), 1, 0) OVER (PARTITION BY u.Id ORDER BY DATE_TRUNC('month', p.CreationDate)) 
            THEN 'Decline'
            ELSE 'Stable'
        END as TrendStatus
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
    GROUP BY u.Id, u.DisplayName, DATE_TRUNC('month', p.CreationDate)
)
SELECT 
    'Performance Benchmark Report' as ReportName,
    COUNT(DISTINCT u.Id) as TotalUsers,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT t.Id) as TotalTags,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.PostTypeId = 1 
        AND p.Score > 100
    ) as HighScoreQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.PostTypeId = 2 
        AND p.Score > 50
    ) as HighScoreAnswers,
    (
        SELECT AVG(Reputation) 
        FROM Users u 
        WHERE u.Reputation > 1000
    ) as AvgHighReputation,
    (
        SELECT COUNT(*) 
        FROM Users u 
        WHERE u.Reputation BETWEEN 1000 AND 10000
    ) as MidTierUsers,
    (
        SELECT COUNT(*) 
        FROM Users u 
        WHERE u.Reputation >= 10000
    ) as HighTierUsers,
    (
        SELECT COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) 
        FROM Posts p 
        JOIN Users u ON p.OwnerUserId = u.Id 
        WHERE u.Reputation >= 10000
    ) as HighRepQuestionCount,
    (
        SELECT COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) 
        FROM Posts p 
        JOIN Users u ON p.OwnerUserId = u.Id 
        WHERE u.Reputation >= 10000
    ) as HighRepAnswerCount,
    (
        SELECT STRING_AGG(CONCAT(u.DisplayName, ': ', u.Reputation), ', ')
        FROM Users u 
        WHERE u.Reputation >= 10000
        ORDER BY u.Reputation DESC
        LIMIT 10
    ) as TopReputationUsers,
    (SELECT COUNT(*) FROM Posts WHERE Score < 0) as NegativeScorePosts,
    (SELECT COUNT(*) FROM Posts WHERE ViewCount > 10000) as HighViewPosts,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.CreationDate >= DATEADD(day, -30, CURRENT_TIMESTAMP)
    ) as RecentPosts30Days,
    (
        SELECT COUNT(*) FROM Posts p 
        WHERE p.CreationDate >= DATEADD(day, -7, CURRENT_TIMESTAMP)
    ) as RecentPosts7Days,
    (
        SELECT AVG(p.ViewCount) 
        FROM Posts p 
        WHERE p.PostTypeId = 1
    ) as AvgQuestionViews,
    (
        SELECT AVG(p.ViewCount) 
        FROM Posts p 
        WHERE p.PostTypeId = 2
    ) as AvgAnswerViews,
    (
        SELECT STRING_AGG(CONCAT('Q', p.Id, ': ', p.Title), '; ')
        FROM Posts p 
        WHERE p.PostTypeId = 1 
        AND p.Score > 100
        ORDER BY p.Score DESC
        LIMIT 5
    ) as TopScoreQuestions,
    (
        SELECT STRING_AGG(CONCAT('A', p.Id, ': ', p.Title), '; ')
        FROM Posts p 
        WHERE p.PostTypeId = 2 
        AND p.Score > 50
        ORDER BY p.Score DESC
        LIMIT 5
    ) as TopScoreAnswers,
    (
        SELECT COUNT(*) 
        FROM Users u 
        WHERE u.AccountId IS NOT NULL
    ) as UsersWithAccounts,
    (
        SELECT COUNT(*) 
        FROM Users u 
        WHERE u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != ''
    ) as UsersWithWebsites,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags IS NOT NULL AND p.Tags != ''
    ) as PostsHavingTags,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.Text LIKE '%help%'
    ) as CommentsWithHelp,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Body LIKE '%code%' AND p.PostTypeId = 1
    ) as QuestionsWithCode,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Body LIKE '%question%' AND p.PostTypeId = 2
    ) as AnswerWithQuestion,
    (
        SELECT COUNT(DISTINCT p.OwnerUserId) 
        FROM Posts p 
        WHERE p.PostTypeId IN (1, 2)
    ) as ActiveAuthors,
    (
        SELECT COUNT(DISTINCT u.Id) 
        FROM Users u 
        WHERE u.Id IN (
            SELECT DISTINCT UserId 
            FROM Badges
            WHERE Date >= DATEADD(month, -6, CURRENT_TIMESTAMP)
        )
    ) as RecentBadgeRecipients,
    (
        SELECT COUNT(DISTINCT p.PostTypeId) 
        FROM Posts p
    ) as DifferentPostTypes,
    (
        SELECT COUNT(DISTINCT p.ParentId) 
        FROM Posts p 
        WHERE p.PostTypeId = 2
    ) as AnsweredQuestions,
    (
        SELECT COUNT(DISTINCT p.AcceptedAnswerId) 
        FROM Posts p 
        WHERE p.PostTypeId = 1
    ) as AcceptedAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.ClosedDate IS NOT NULL
    ) as ClosedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.CommunityOwnedDate IS NOT NULL
    ) as CommunityOwnedPosts,
    (
        SELECT COUNT(DISTINCT p.UserId) 
        FROM PostHistory p 
        WHERE p.PostHistoryTypeId = 10
    ) as CloseVoteUsers,
    (
        SELECT COUNT(DISTINCT p.UserId) 
        FROM PostHistory p 
        WHERE p.PostHistoryTypeId = 6
    ) as TagEditUsers,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.LinkTypeId = 3
    ) as DuplicateLinks,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.LinkTypeId = 1
    ) as RegularLinks,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.VoteTypeId = 2
    ) as UpVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.VoteTypeId = 3
    ) as DownVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.VoteTypeId = 5
    ) as FavoriteVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.VoteTypeId = 6
    ) as CloseVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.VoteTypeId = 14
    ) as ModeratorVotes,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.Class = 1
    ) as GoldBadges,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.Class = 2
    ) as SilverBadges,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.Class = 3
    ) as BronzeBadges,
    (
        SELECT COUNT(DISTINCT u.Id) 
        FROM Users u 
        WHERE u.Views > 10000
    ) as HighViewUsers,
    (
        SELECT COUNT(*) 
        FROM Users u 
        WHERE u.UpVotes > 1000
    ) as HighUpVoteUsers,
    (
        SELECT COUNT(*) 
        FROM Users u 
        WHERE u.DownVotes > 1000
    ) as HighDownVoteUsers,
    (
        SELECT COUNT(*) 
        FROM Tags t 
        WHERE t.Count > 5000
    ) as PopularTags,
    (
        SELECT COUNT(*) 
        FROM Tags t 
        WHERE t.Count > 1000 AND t.Count < 5000
    ) as MediumTags,
    (
        SELECT COUNT(*) 
        FROM Tags t 
        WHERE t.Count < 1000
    ) as LessPopularTags,
    (
        SELECT AVG(u.Reputation) 
        FROM Users u 
        WHERE u.Reputation > 0
    ) as AvgReputation,
    (
        SELECT MAX(u.Reputation) 
        FROM Users u
    ) as MaxReputation,
    (
        SELECT MIN(u.Reputation) 
        FROM Users u
    ) as MinReputation,
    (
        SELECT AVG(p.Score) 
        FROM Posts p
    ) as AvgPostScore,
    (
        SELECT MAX(p.Score) 
        FROM Posts p
    ) as MaxPostScore,
    (
        SELECT MIN(p.Score) 
        FROM Posts p
    ) as MinPostScore,
    (
        SELECT AVG(p.ViewCount) 
        FROM Posts p
    ) as AvgPostViews,
    (
        SELECT MAX(p.ViewCount) 
        FROM Posts p
    ) as MaxPostViews,
    (
        SELECT MIN(p.ViewCount) 
        FROM Posts p
    ) as MinPostViews,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Title IS NOT NULL AND p.Title != ''
    ) as PostsHavingTitles,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Body IS NOT NULL AND p.Body != ''
    ) as PostsHavingBodies,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.Text IS NOT NULL AND c.Text != ''
    ) as CommentsWithText,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.Text IS NOT NULL AND ph.Text != ''
    ) as PostHistoryWithText,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.Name IS NOT NULL AND b.Name != ''
    ) as BadgesWithNames,
    (
        SELECT COUNT(*) 
        FROM Users u 
        WHERE u.DisplayName IS NOT NULL AND u.DisplayName != ''
    ) as UsersWithDisplayNames,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags IS NOT NULL AND p.Tags != '' AND p.Tags LIKE '%<%'
    ) as QuestionTagsPresent,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.Tags IS NULL OR p.Tags = ''
    ) as QuestionTagsMissing,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.LastActivityDate > DATEADD(day, -7, CURRENT_TIMESTAMP)
    ) as RecentlyActivePosts,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.LastActivityDate > DATEADD(day, -30, CURRENT_TIMESTAMP)
    ) as RecentlyActivePosts30Days,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.CreationDate < DATEADD(year, -1, CURRENT_TIMESTAMP)
    ) as OldPosts,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
    ) as RecentPosts,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.CreationDate BETWEEN DATEADD(year, -2, CURRENT_TIMESTAMP) AND DATEADD(year, 0, CURRENT_TIMESTAMP)
    ) as PostsLast2Years,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate > DATEADD(year, -1, CURRENT_TIMESTAMP)
    ) as RecentQuestionsAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate <= DATEADD(year, -1, CURRENT_TIMESTAMP)
    ) as OldQuestionsAnswers;