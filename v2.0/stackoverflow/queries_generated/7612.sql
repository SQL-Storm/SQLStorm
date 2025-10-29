-- {"query": "7612.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2690} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High Activity'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium Activity'
            ELSE 'Low Activity'
        END as ActivityLevel,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            WHEN u.Reputation >= 100 THEN 'Beginner'
            ELSE 'Novice'
        END as ReputationLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankByScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RankByDate,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPostsPerUser,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.DeletedDate IS NULL
),
TagAnalytics AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular Tag'
            WHEN t.Count > 100 THEN 'Moderate Tag' 
            ELSE 'Niche Tag'
        END as TagPopularity,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank,
        PERCENT_RANK() OVER (ORDER BY t.Count) as PercentileRank
    FROM Tags t
    WHERE t.Count > 0
),
UserPostEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as PostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswersGiven,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
        MAX(p.CreationDate) as LastActivity,
        DATEDIFF(day, u.CreationDate, MAX(p.CreationDate)) as DaysActive,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as UserActivityRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= DATEADD(year, -2, GETDATE())
    GROUP BY u.Id, u.DisplayName
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostTypeId,
        CASE 
            WHEN p.AnswerCount > 0 AND p.Score > 10 THEN 'High Value'
            WHEN p.AnswerCount > 0 AND p.Score > 0 THEN 'Good Value'
            WHEN p.AnswerCount = 0 AND p.Score > 5 THEN 'High Engagement No Answers'
            ELSE 'Low Engagement'
        END as PostValueCategory,
        CASE 
            WHEN p.Tags IS NULL OR LEN(p.Tags) < 3 THEN 'No Tags'
            WHEN LEN(p.Tags) BETWEEN 3 AND 10 THEN 'Few Tags'
            WHEN LEN(p.Tags) BETWEEN 11 AND 20 THEN 'Medium Tags'
            ELSE 'Many Tags'
        END as TagDensityCategory,
        DATEDIFF(day, p.CreationDate, GETDATE()) as DaysSinceCreation,
        CASE 
            WHEN p.CreationDate >= DATEADD(day, -30, GETDATE()) THEN 'Recent'
            WHEN p.CreationDate >= DATEADD(day, -90, GETDATE()) THEN 'Last Quarter'
            WHEN p.CreationDate >= DATEADD(day, -365, GETDATE()) THEN 'Last Year'
            ELSE 'Old'
        END as AgeCategory,
        p.Tags,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END as PostStatus
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.DeletedDate IS NULL
        AND (p.OwnerUserId IS NOT NULL OR p.OwnerDisplayName IS NOT NULL)
)
SELECT 
    'Performance Benchmark Report' as ReportName,
    GETDATE() as ReportTimestamp,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT ua.UserId) as DistinctUsers,
    COUNT(DISTINCT tp.PostId) as DistinctPosts,
    COUNT(DISTINCT ta.TagName) as DistinctTags,
    COUNT(DISTINCT up.UserId) as ActiveUsers,
    AVG(CAST(ua.TotalPosts as FLOAT)) as AvgPostsPerUser,
    AVG(ua.TotalComments) as AvgCommentsPerUser,
    AVG(ua.TotalBadges) as AvgBadgesPerUser,
    SUM(ua.TotalPostScore) as TotalPostScore,
    SUM(ua.TotalViews) as TotalViews,
    AVG(CAST(tp.Score as FLOAT)) as AvgPostScore,
    AVG(CAST(tp.ViewCount as FLOAT)) as AvgViewCount,
    MAX(ua.Reputation) as MaxReputation,
    MIN(ua.Reputation) as MinReputation,
    COUNT(*) FILTER (WHERE ua.ActivityLevel = 'High Activity') as HighActivityUsers,
    COUNT(*) FILTER (WHERE ua.ReputationLevel = 'Expert') as ExpertUsers,
    COUNT(*) FILTER (WHERE tp.PostValueCategory = 'High Value') as HighValuePosts,
    COUNT(*) FILTER (WHERE tp.AgeCategory = 'Recent') as RecentPosts,
    COUNT(*) FILTER (WHERE ta.TagPopularity = 'Popular Tag') as PopularTags,
    COUNT(*) FILTER (WHERE tp.PostStatus = 'Open') as OpenPosts,
    COUNT(*) FILTER (WHERE up.PostsCreated > 50) as HighActivityUsersCount,
    COUNT(*) FILTER (WHERE ta.PopularityRank <= 10) as Top10TagsCount,
    COUNT(*) FILTER (WHERE tp.Score > 100) as HighlyRatedPostsCount,
    COUNT(*) FILTER (WHERE up.DaysActive > 365) as LongTermActiveUsersCount,
    (
        SELECT COUNT(*) 
        FROM Posts p1 
        JOIN Posts p2 ON p1.ParentId = p2.Id 
        WHERE p1.PostTypeId = 2 AND p2.PostTypeId = 1 AND p1.DeletedDate IS NULL
    ) as AnswerQuestionLinkCount,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id 
        WHERE pht.Name LIKE '%Edit%' OR pht.Name LIKE '%Title%'
    ) as EditHistoryCount,
    (
        SELECT COUNT(*) 
        FROM Comments c1 
        JOIN Posts p3 ON c1.PostId = p3.Id 
        WHERE c1.Score > 10 AND p3.PostTypeId = 1
    ) as HighScoreCommentsCount,
    (
        SELECT COUNT(*) 
        FROM Badges b1 
        JOIN Users u1 ON b1.UserId = u1.Id 
        WHERE b1.Date >= DATEADD(month, -6, GETDATE()) AND u1.Reputation > 1000
    ) as RecentBadgesHighReputationCount,
    (
        SELECT COUNT(*) 
        FROM Tags t1 
        WHERE t1.Count > 500 AND t1.IsRequired = 1
    ) as RequiredPopularTagsCount,
    (
        SELECT COUNT(*) 
        FROM Votes v1 
        JOIN PostHistory ph1 ON v1.PostId = ph1.PostId 
        WHERE v1.VoteTypeId = 2 AND ph1.PostHistoryTypeId = 5
    ) as UpvotesOnEditsCount,
    (
        SELECT COUNT(*) 
        FROM Posts p4 
        JOIN Users u2 ON p4.OwnerUserId = u2.Id 
        WHERE u2.Reputation > 10000 AND p4.CreationDate >= DATEADD(month, -1, GETDATE())
    ) as ActiveExpertPostsCount,
    (
        SELECT COUNT(*) 
        FROM Posts p5 
        LEFT JOIN PostLinks pl ON p5.Id = pl.PostId 
        WHERE pl.Id IS NULL AND p5.PostTypeId = 1 AND p5.DeletedDate IS NULL
    ) as UnlinkedQuestionsCount,
    (
        SELECT COUNT(*) 
        FROM Users u3 
        JOIN Posts p6 ON u3.Id = p6.OwnerUserId 
        WHERE u3.Views > 1000 AND p6.PostTypeId = 1 AND p6.DeletedDate IS NULL
    ) as HighViewUsersCount,
    (
        SELECT COUNT(*) 
        FROM Posts p7 
        JOIN Votes v2 ON p7.Id = v2.PostId 
        WHERE v2.VoteTypeId IN (2, 3) AND p7.PostTypeId = 2 AND p7.DeletedDate IS NULL
    ) as AnswerVotesCount,
    (
        SELECT COUNT(*) 
        FROM Posts p8 
        WHERE p8.PostTypeId = 1 AND p8.AnswerCount > 10 AND p8.DeletedDate IS NULL
    ) as HighlyAnsweredQuestionsCount
FROM UserActivityStats ua
FULL OUTER JOIN TopPosts tp ON 1=1
FULL OUTER JOIN TagAnalytics ta ON 1=1
FULL OUTER JOIN UserPostEngagement up ON 1=1
FULL OUTER JOIN ComplexPostAnalysis ca ON 1=1
WHERE (ua.UserId IS NOT NULL OR tp.PostId IS NOT NULL OR ta.TagName IS NOT NULL OR up.UserId IS NOT NULL OR ca.PostId IS NOT NULL)
    AND ua.Reputation > 100
    AND tp.Score > 0
    AND ta.TagCount > 10
    AND up.PostsCreated > 0
    AND ca.Score > 0
    AND (CASE 
        WHEN ua.ActivityLevel = 'High Activity' THEN 1
        WHEN tp.PostValueCategory = 'High Value' THEN 1  
        WHEN ta.TagPopularity = 'Popular Tag' THEN 1
        WHEN up.UserActivityRank <= 100 THEN 1
        WHEN ca.AgeCategory = 'Recent' THEN 1
        ELSE 0 
    END) = 1
HAVING COUNT(*) > 0
ORDER BY COUNT(*) DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;