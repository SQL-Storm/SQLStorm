-- {"query": "7505.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2802} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Veteran'
            WHEN u.Reputation > 100 THEN 'Active'
            ELSE 'Newbie'
        END as RepTier,
        STRING_AGG(DISTINCT p.Title, ', ') as PostTitles,
        COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) as PositiveScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) as NegativeScorePosts,
        AVG(p.Score) as AvgPostScore,
        COUNT(DISTINCT c.Id) as CommentsMade,
        COUNT(DISTINCT v.Id) as VotesReceived,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalQuestionViews,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) as TotalAnswerViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0 
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId IN (1, 5) THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId IN (4, 6) THEN 'Tag'
            ELSE 'Other'
        END as PostCategory,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE 
            WHEN p.Score >= 100 THEN 'Hot'
            WHEN p.Score >= 10 THEN 'Popular'
            WHEN p.Score >= 0 THEN 'Normal'
            WHEN p.Score < 0 THEN 'Controversial'
            ELSE 'Unknown'
        END as PopularityLevel,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 2
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 3
            ELSE 0
        END as StatusCategory,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as AgeDays,
        COALESCE(p.Tags, '') as Tags,
        LENGTH(p.Tags) as TagLength,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        COUNT(DISTINCT pl.Id) as LinkCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(v.Score) as AvgVoteScore
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.Id > 0
    GROUP BY p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.ParentId, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.AcceptedAnswerId, p.Tags
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Niche'
        END as PopularityGroup,
        CASE 
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            WHEN t.IsRequired = 1 THEN 'Required'
            ELSE 'Regular'
        END as TagType,
        STRING_AGG(p.Title, ' | ') as AssociatedPosts,
        COUNT(DISTINCT COALESCE(p.OwnerUserId, 0)) as ActiveUsers,
        AVG(COALESCE(p.Score, 0)) as AvgScore,
        MAX(COALESCE(p.CreationDate, CURRENT_TIMESTAMP)) as LatestPostDate
    FROM Tags t
    LEFT JOIN Posts p ON t.Id = COALESCE(p.ParentId, 0)
    WHERE t.TagName IS NOT NULL
    GROUP BY t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired
)
SELECT 
    'Overall Performance Analysis' as Category,
    COUNT(DISTINCT u.Id) as TotalUsers,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT t.Id) as TotalTags,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT ph.Id) as TotalHistoryEntries,
    COUNT(DISTINCT pl.Id) as TotalPostLinks,
    COUNT(DISTINCT v.Id) as TotalVotes,
    AVG(u.Reputation) as AvgReputation,
    AVG(p.Score) as AvgPostScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) as AvgQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount END) as AvgAnswerViews,
    STRING_AGG(DISTINCT u.DisplayName, ', ') as AllUserNames,
    STRING_AGG(DISTINCT t.TagName, ', ') as AllTags,
    STRING_AGG(DISTINCT p.Title, ', ') as AllPostTitles,
    (SELECT COUNT(*) FROM Posts p WHERE p.ClosedDate IS NOT NULL AND p.PostTypeId = 1) as ClosedQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1) as AcceptedQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.ParentId IS NOT NULL AND p.PostTypeId = 2) as AnsweredQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) < 30) as RecentQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) < 30) as RecentAnswers,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation > 10000) as EliteUsers,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation BETWEEN 1000 AND 10000) as VeteranUsers,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation BETWEEN 100 AND 1000) as ActiveUsers,
    (SELECT COUNT(*) FROM Users u WHERE u.Reputation < 100) as NewbieUsers,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score > 100) as HighScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score > 0 AND p.Score < 100) as MediumScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.Score < 0) as NegativeScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount > 1000) as HighlyViewedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount > 100 AND p.ViewCount <= 1000) as ModeratelyViewedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount <= 100) as LowViewedPosts,
    
    -- Complex calculated fields
    AVG(CASE WHEN p.Score > 0 THEN p.ViewCount ELSE NULL END) as AvgViewsForPositivePosts,
    AVG(CASE WHEN p.Score < 0 THEN p.ViewCount ELSE NULL END) as AvgViewsForNegativePosts,
    (SELECT COUNT(*) FROM (
        SELECT u.Id 
        FROM Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId = 1 AND p.Score > 100
        GROUP BY u.Id HAVING COUNT(*) > 1
    ) x) as ActiveQuestionAuthors,
    (SELECT COUNT(*) FROM (
        SELECT u.Id 
        FROM Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId = 2 AND p.Score > 50
        GROUP BY u.Id HAVING COUNT(*) > 2
    ) x) as ActiveAnswerAuthors,
    
    -- Window function calculations
    ROW_NUMBER() OVER (ORDER BY AVG(p.Score) DESC) as ScoreRank,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.OwnerUserId) DESC) as AuthorRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) DESC) as QuestionRank,
    PERCENT_RANK() OVER (ORDER BY AVG(p.ViewCount)) as ViewPercentile,
    
    -- Aggregated string functions
    CONCAT('Total Users: ', COUNT(DISTINCT u.Id)) as MetricSummary,
    
    -- Subquery with correlated reference
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) as UserQuestionCount,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 2) as UserAnswerCount,
    
    -- Set operators (this would normally involve different datasets)
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE '%python%') as PythonTagQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE '%java%') as JavaTagQuestions,
    
    -- Complex predicates with NULL handling
    SUM(CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN 1 ELSE 0 END) as UsersWithWebsite,
    SUM(CASE WHEN u.Location IS NOT NULL AND u.Location != '' THEN 1 ELSE 0 END) as UsersWithLocation,
    SUM(CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 10 THEN 1 ELSE 0 END) as UsersWithBio,
    
    -- NULL-safe aggregations
    AVG(CASE WHEN u.UpVotes IS NOT NULL THEN u.UpVotes ELSE 0 END) as AvgUpVotes,
    AVG(CASE WHEN u.DownVotes IS NOT NULL THEN u.DownVotes ELSE 0 END) as AvgDownVotes,
    
    -- Nested subqueries and complex conditions
    (SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 1 AND p.OwnerUserId IN (
        SELECT u2.Id FROM Users u2 WHERE u2.Reputation > 1000
    )) as HighRepQuestionAvgScore,
    
    -- Multiple JOINs with complex conditions
    (SELECT COUNT(DISTINCT p.Id) FROM Posts p 
     JOIN Users u ON p.OwnerUserId = u.Id 
     JOIN Badges b ON u.Id = b.UserId 
     WHERE p.PostTypeId = 1 AND u.Reputation > 500 AND b.Class = 1) as GoldBadgeQuestionAuthors
    
FROM Users u
FULL OUTER JOIN Posts p ON u.Id = p.OwnerUserId
FULL OUTER JOIN Tags t ON 1 = 1
FULL OUTER JOIN Badges b ON u.Id = b.UserId
FULL OUTER JOIN Comments c ON u.Id = c.UserId
FULL OUTER JOIN PostHistory ph ON p.Id = ph.PostId
FULL OUTER JOIN PostLinks pl ON p.Id = pl.PostId
FULL OUTER JOIN Votes v ON p.Id = v.PostId
WHERE u.Id IS NOT NULL OR p.Id IS NOT NULL OR t.Id IS NOT NULL
GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.WebsiteUrl, u.Location, u.AboutMe
HAVING COUNT(u.Id) > 0
ORDER BY TotalUsers DESC, TotalPosts DESC
LIMIT 10000;