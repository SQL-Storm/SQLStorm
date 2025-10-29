-- {"query": "7794.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 9946} 
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
        COALESCE(MAX(p.LastActivityDate), u.LastAccessDate) as LastActivity,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) as AvgQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE NULL END) as AvgAnswerViews,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END, ' | ') as QuestionTags,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) as QuestionsWithComments,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.FavoriteCount, 0) ELSE 0 END) as TotalFavorites,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as AcceptedAnswers,
        DATEDIFF(day, u.CreationDate, COALESCE(MAX(p.CreationDate), u.CreationDate)) as AccountAgeDays,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as ActivityRank,
        NTILE(10) OVER (ORDER BY u.Reputation DESC) as ReputationDecile,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Elite'
            WHEN COUNT(DISTINCT p.Id) > 500 THEN 'Veteran'
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Experienced'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
            ELSE 'New'
        END as UserStatus,
        COALESCE(SUM(p.Score), 0) + COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) as EffectiveScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.Tags,
        CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END as AnswerCountIfQuestion,
        CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END as ScoreIfAnswer,
        CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END as ViewCountIfQuestion,
        CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE NULL END as ViewCountIfAnswer,
        CASE 
            WHEN p.Score > 100 THEN 'Gold'
            WHEN p.Score > 50 THEN 'Silver'
            WHEN p.Score > 10 THEN 'Bronze'
            ELSE 'Common'
        END as ScoreTier,
        CASE 
            WHEN p.ViewCount > 5000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Regular'
        END as PopularityTier,
        DATEDIFF(day, p.CreationDate, COALESCE(p.LastActivityDate, p.CreationDate)) as DaysActive,
        CAST(p.Score AS FLOAT) / NULLIF(p.ViewCount, 0) as ScorePerView,
        CAST(p.AnswerCount AS FLOAT) / NULLIF(p.ViewCount, 0) as AnswersPerView,
        CASE WHEN p.PostTypeId = 1 AND p.PostTypeId = p.ParentId THEN 1 ELSE 0 END as SelfReferenced,
        p.ContentLicense,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.AcceptedAnswerId
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostMetrics AS (
    SELECT 
        PostId,
        Title,
        Score,
        ViewCount,
        AnswerCount,
        CommentCount,
        FavoriteCount,
        CreationDate,
        LastActivityDate,
        PostTypeId,
        OwnerUserId,
        OwnerDisplayName,
        Tags,
        AnswerCountIfQuestion,
        ScoreIfAnswer,
        ViewCountIfQuestion,
        ViewCountIfAnswer,
        ScoreTier,
        PopularityTier,
        DaysActive,
        ScorePerView,
        AnswersPerView,
        SelfReferenced,
        ContentLicense,
        ClosedDate,
        CommunityOwnedDate,
        AcceptedAnswerId,
        AVG(ScorePerView) OVER () as AvgScorePerView,
        AVG(ViewCount) OVER () as AvgViewCount,
        AVG(AnswerCount) OVER () as AvgAnswerCount,
        STDDEV(ScorePerView) OVER () as StdDevScorePerView,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ScorePerView) OVER () as MedianScorePerView,
        LAG(ScorePerView, 1) OVER (ORDER BY CreationDate) as PreviousScorePerView,
        LEAD(ScorePerView, 1) OVER (ORDER BY CreationDate) as NextScorePerView,
        ROW_NUMBER() OVER (ORDER BY Score DESC) as HighScoreRank,
        RANK() OVER (ORDER BY ViewCount DESC) as HighViewRank,
        DENSE_RANK() OVER (ORDER BY DaysActive DESC) as ActiveRank,
        NTILE(10) OVER (ORDER BY Score DESC) as ScoreDecile,
        CASE 
            WHEN ScorePerView > 0.5 THEN 'Excellent'
            WHEN ScorePerView > 0.2 THEN 'Good'
            WHEN ScorePerView > 0.05 THEN 'Average'
            ELSE 'Poor'
        END as QualityRank,
        COALESCE(ClosedDate, CommunityOwnedDate) as EventDate,
        CASE 
            WHEN ClosedDate IS NOT NULL THEN 'Closed'
            WHEN CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END as Status
    FROM PostPerformance
),
UserPostAggregates AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        MIN(p.Score) as MinScore,
        SUM(p.ViewCount) as TotalViews,
        AVG(p.ViewCount) as AvgViews,
        MAX(p.ViewCount) as MaxViews,
        MIN(p.ViewCount) as MinViews,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as Answers,
        COUNT(p.Id) OVER () as OverallTotalPosts,
        COUNT(p.Id) OVER (PARTITION BY u.Id) as UserTotalPosts,
        AVG(COUNT(p.Id) OVER (PARTITION BY u.Id)) OVER () as AvgUserPosts,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
)
SELECT 
    '=== PERFORMANCE BENCHMARK QUERY ===' as QueryInfo,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT u.Id) as UniqueUsers,
    COUNT(DISTINCT p.Id) as UniquePosts,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT ph.Id) as TotalPostHistory,
    COUNT(DISTINCT pl.Id) as TotalPostLinks,
    COUNT(DISTINCT t.Id) as TotalTags,
    COUNT(DISTINCT vt.Id) as TotalVoteTypes,
    STRING_AGG(DISTINCT u.DisplayName, ', ') as UserNames,
    STRING_AGG(DISTINCT p.Title, ', ') as PostTitles,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagNames,
    STRING_AGG(DISTINCT ph.PostHistoryTypeId, ', ') as PostHistoryTypes,
    STRING_AGG(DISTINCT pl.LinkTypeId, ', ') as LinkTypes,
    STRING_AGG(DISTINCT vt.Name, ', ') as VoteTypeNames,
    MIN(u.CreationDate) as EarliestUserDate,
    MAX(u.CreationDate) as LatestUserDate,
    MIN(p.CreationDate) as EarliestPostDate,
    MAX(p.CreationDate) as LatestPostDate,
    AVG(u.Reputation) as AvgReputation,
    AVG(p.Score) as AvgScore,
    AVG(p.ViewCount) as AvgViews,
    AVG(p.AnswerCount) as AvgAnswers,
    AVG(p.CommentCount) as AvgComments,
    MAX(u.Views) as MaxUserViews,
    MAX(p.Score) as MaxPostScore,
    MAX(p.ViewCount) as MaxPostViews,
    SUM(b.Id) as BadgeSum,
    SUM(c.Id) as CommentSum,
    SUM(ph.Id) as PostHistorySum,
    SUM(pl.Id) as PostLinkSum,
    SUM(t.Id) as TagSum,
    SUM(vt.Id) as VoteTypeSum,
    COUNT(CASE WHEN u.Reputation > 10000 THEN 1 END) as HighReputationUsers,
    COUNT(CASE WHEN p.Score > 100 THEN 1 END) as HighScorePosts,
    COUNT(CASE WHEN p.ViewCount > 5000 THEN 1 END) as HighViewPosts,
    COUNT(CASE WHEN p.AnswerCount > 10 THEN 1 END) as HighAnswerPosts,
    COUNT(CASE WHEN p.CommentCount > 5 THEN 1 END) as HighCommentPosts,
    COUNT(CASE WHEN p.FavoriteCount > 10 THEN 1 END) as HighFavoritePosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as QuestionPosts,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as AnswerPosts,
    COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 END) as ClosedPosts,
    COUNT(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 END) as CommunityOwnedPosts,
    COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) as AcceptedAnswerPosts,
    COUNT(CASE WHEN p.ParentId IS NOT NULL THEN 1 END) as AnswerToQuestionPosts,
    COUNT(CASE WHEN p.ParentId IS NULL THEN 1 END) as QuestionPostsOnly,
    COUNT(CASE WHEN u.EmailHash IS NOT NULL THEN 1 END) as UsersWithEmail,
    COUNT(CASE WHEN u.WebsiteUrl IS NOT NULL THEN 1 END) as UsersWithWebsite,
    COUNT(CASE WHEN u.Location IS NOT NULL THEN 1 END) as UsersWithLocation,
    COUNT(CASE WHEN u.AboutMe IS NOT NULL THEN 1 END) as UsersWithAbout,
    COUNT(CASE WHEN p.Tags IS NOT NULL THEN 1 END) as PostsWithTags,
    COUNT(CASE WHEN p.Body IS NOT NULL THEN 1 END) as PostsWithBody,
    COUNT(CASE WHEN c.Text IS NOT NULL THEN 1 END) as CommentsWithText,
    COUNT(CASE WHEN ph.Text IS NOT NULL THEN 1 END) as PostHistoriesWithText,
    COUNT(CASE WHEN pl.RelatedPostId IS NOT NULL THEN 1 END) as PostLinksWithRelated,
    COUNT(CASE WHEN t.ExcerptPostId IS NOT NULL THEN 1 END) as TagsWithExcerpt,
    COUNT(CASE WHEN t.WikiPostId IS NOT NULL THEN 1 END) as TagsWithWiki,
    COUNT(CASE WHEN b.Date IS NOT NULL THEN 1 END) as BadgesWithDate,
    COUNT(CASE WHEN ph.Comment IS NOT NULL THEN 1 END) as PostHistoriesWithComment,
    COUNT(CASE WHEN ph.RevisionGUID IS NOT NULL THEN 1 END) as PostHistoriesWithRevision,
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END as HasRecords,
    CASE WHEN COUNT(*) > 10000 THEN 'Large Dataset' ELSE 'Small Dataset' END as DatasetSize,
    (SELECT COUNT(DISTINCT UserId) FROM PostMetrics WHERE ScoreTier = 'Gold') as GoldTierUsers,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScoreTier = 'Gold') as GoldTierPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScoreTier IN ('Silver', 'Gold')) as SilverOrGoldPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE PopularityTier IN ('Viral', 'Popular')) as HighPopularityPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE DaysActive > 365) as LongActivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView > 0.5) as HighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > 100) as VeryAnsweredPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ViewCount > 10000) as VeryViewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE FavoriteCount > 100) as VeryFavoritedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE CommentCount > 100) as VeryCommentedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Status = 'Closed') as ClosedPostsCount,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Status = 'Community Owned') as CommunityOwnedCount,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Status = 'Active') as ActivePostsCount,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE ScoreRank <= 100) as TopScoringUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE ActivityRank <= 100) as TopActivityUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE ReputationDecile = 10) as TopDecileUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Elite') as EliteUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Veteran') as VeteranUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Experienced') as ExperiencedUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Active') as ActiveUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'New') as NewUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 100000) as VeryHighEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 10000) as HighEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 1000) as MediumEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 100) as LowEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 0) as PositiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore = 0) as ZeroScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore < 0) as NegativeScoreUsers,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView > 1.0) as ExtremelyHighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView BETWEEN 0.5 AND 1.0) as VeryHighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView BETWEEN 0.2 AND 0.5) as HighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView BETWEEN 0.05 AND 0.2) as AverageValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView < 0.05) as LowValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView IS NULL) as NullValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView = 0) as ZeroValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView > 0.5) as VeryHighAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView BETWEEN 0.1 AND 0.5) as HighAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView < 0.1) as LowAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView IS NULL) as NullAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > 0 AND ViewCount > 0) as AnsweredViewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount = 0 AND ViewCount > 0) as UnansweredViewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > 0 AND ViewCount = 0) as AnsweredUnviewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount = 0 AND ViewCount = 0) as UnansweredUnviewedPosts,
    (SELECT AVG(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) as AvgScorePerViewAll,
    (SELECT MIN(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) as MinScorePerViewAll,
    (SELECT MAX(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) as MaxScorePerViewAll,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView BETWEEN (SELECT AVG(ScorePerView) - STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) AND (SELECT AVG(ScorePerView) + STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as NormalRangePosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView > (SELECT AVG(ScorePerView) + 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as OutlierHighPosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView < (SELECT AVG(ScorePerView) - 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as OutlierLowPosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView BETWEEN (SELECT AVG(ScorePerView) + STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) AND (SELECT AVG(ScorePerView) + 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as HighRangePosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView BETWEEN (SELECT AVG(ScorePerView) - 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) AND (SELECT AVG(ScorePerView) - STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as LowRangePosts,
    (SELECT AVG(AnswerCount) FROM PostMetrics WHERE AnswerCount IS NOT NULL) as AvgAnswersAll,
    (SELECT AVG(ViewCount) FROM PostMetrics WHERE ViewCount IS NOT NULL) as AvgViewsAll,
    (SELECT AVG(Score) FROM PostMetrics WHERE Score IS NOT NULL) as AvgScoreAll,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > (SELECT AVG(AnswerCount) FROM PostMetrics WHERE AnswerCount IS NOT NULL)) as AboveAvgAnswerPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ViewCount > (SELECT AVG(ViewCount) FROM PostMetrics WHERE ViewCount IS NOT NULL)) as AboveAvgViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score > (SELECT AVG(Score) FROM PostMetrics WHERE Score IS NOT NULL)) as AboveAvgScorePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE DaysActive > (SELECT AVG(DaysActive) FROM PostMetrics WHERE DaysActive IS NOT NULL)) as AboveAvgActivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView > (SELECT AVG(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as AboveAvgScorePerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView > (SELECT AVG(AnswersPerView) FROM PostMetrics WHERE AnswersPerView IS NOT NULL)) as AboveAvgAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score > 0 AND AnswerCount > 0 AND ViewCount > 0) as ActivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score = 0 AND AnswerCount = 0 AND ViewCount = 0) as InactivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score > 0 OR AnswerCount > 0 OR ViewCount > 0) as PositivePosts
FROM Users u
FULL OUTER JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON 1 = 1
LEFT JOIN VoteTypes vt ON 1 = 1
WHERE u.Id IS NOT NULL OR p.Id IS NOT NULL OR b.Id IS NOT NULL OR c.Id IS NOT NULL OR ph.Id IS NOT NULL OR pl.Id IS NOT NULL OR t.Id IS NOT NULL OR vt.Id IS NOT NULL
  AND (u.Id IS NOT NULL OR b.Id IS NOT NULL OR c.Id IS NOT NULL OR ph.Id IS NOT NULL OR pl.Id IS NOT NULL OR t.Id IS NOT NULL OR vt.Id IS NOT NULL)
  AND (
    (SELECT COUNT(*) FROM UserActivityStats WHERE ScoreRank <= 50) > 0
    OR (SELECT COUNT(*) FROM UserActivityStats WHERE ActivityRank <= 50) > 0
    OR (SELECT COUNT(*) FROM PostMetrics WHERE ScoreTier = 'Gold') > 0
    OR (SELECT COUNT(*) FROM PostMetrics WHERE PopularityTier IN ('Viral', 'Popular')) > 0
  )
  AND (p.PostTypeId IS NULL OR p.PostTypeId IN (1, 2))
  AND (p.Score IS NULL OR p.Score > -1000)
  AND (p.ViewCount IS NULL OR p.ViewCount >= 0)
  AND (p.AnswerCount IS NULL OR p.AnswerCount >= 0)
  AND (p.CommentCount IS NULL OR p.CommentCount >= 0)
  AND (p.FavoriteCount IS NULL OR p.FavoriteCount >= 0)
  AND (u.Reputation IS NULL OR u.Reputation >= 0)
  AND (u.Views IS NULL OR u.Views >= 0)
  AND (u.UpVotes IS NULL OR u.UpVotes >= 0)
  AND (u.DownVotes IS NULL OR u.DownVotes >= 0)
  AND (b.Id IS NULL OR b.Id > 0)
  AND (c.Id IS NULL OR c.Id > 0)
  AND (ph.Id IS NULL OR ph.Id > 0)
  AND (pl.Id IS NULL OR pl.Id > 0)
  AND (t.Id IS NULL OR t.Id > 0)
  AND (vt.Id IS NULL OR vt.Id > 0)
  AND (u.CreationDate IS NULL OR u.CreationDate > '2000-01-01')
  AND (p.CreationDate IS NULL OR p.CreationDate > '2000-01-01')
  AND (c.CreationDate IS NULL OR c.CreationDate > '2000-01-01')
  AND (ph.CreationDate IS NULL OR ph.CreationDate > '2000-01-01')
  AND (pl.CreationDate IS NULL OR pl.CreationDate > '2000-01-01')
  AND (
    (u.DisplayName IS NULL OR LENGTH(u.DisplayName) > 0)
    AND (p.Title IS NULL OR LENGTH(p.Title) > 0)
    AND (b.Name IS NULL OR LENGTH(b.Name) > 0)
    AND (t.TagName IS NULL OR LENGTH(t.TagName) > 0)
    AND (c.Text IS NULL OR LENGTH(c.Text) > 0)
    AND (ph.Text IS NULL OR LENGTH(ph.Text) > 0)
    AND (pl.RelatedPostId IS NULL OR pl.RelatedPostId > 0)
  )
  AND COALESCE(p.Score, 0) + COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) +
      COALESCE(p.CommentCount, 0) + COALESCE(p.FavoriteCount, 0) + COALESCE(u.Reputation, 0) +
      COALESCE(u.Views, 0) + COALESCE(u.UpVotes, 0) + COALESCE(u.DownVotes, 0) > -10000
HAVING COUNT(*) > 0
UNION ALL
SELECT 
    '=== PERFORMANCE ENHANCED QUERY ===' as QueryInfo,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT u.Id) as UniqueUsers,
    COUNT(DISTINCT p.Id) as UniquePosts,
    COUNT(DISTINCT b.Id) as TotalBadges,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT ph.Id) as TotalPostHistory,
    COUNT(DISTINCT pl.Id) as TotalPostLinks,
    COUNT(DISTINCT t.Id) as TotalTags,
    COUNT(DISTINCT vt.Id) as TotalVoteTypes,
    STRING_AGG(DISTINCT u.DisplayName, ', ') as UserNames,
    STRING_AGG(DISTINCT p.Title, ', ') as PostTitles,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagNames,
    STRING_AGG(DISTINCT ph.PostHistoryTypeId, ', ') as PostHistoryTypes,
    STRING_AGG(DISTINCT pl.LinkTypeId, ', ') as LinkTypes,
    STRING_AGG(DISTINCT vt.Name, ', ') as VoteTypeNames,
    MIN(u.CreationDate) as EarliestUserDate,
    MAX(u.CreationDate) as LatestUserDate,
    MIN(p.CreationDate) as EarliestPostDate,
    MAX(p.CreationDate) as LatestPostDate,
    AVG(u.Reputation) as AvgReputation,
    AVG(p.Score) as AvgScore,
    AVG(p.ViewCount) as AvgViews,
    AVG(p.AnswerCount) as AvgAnswers,
    AVG(p.CommentCount) as AvgComments,
    MAX(u.Views) as MaxUserViews,
    MAX(p.Score) as MaxPostScore,
    MAX(p.ViewCount) as MaxPostViews,
    SUM(b.Id) as BadgeSum,
    SUM(c.Id) as CommentSum,
    SUM(ph.Id) as PostHistorySum,
    SUM(pl.Id) as PostLinkSum,
    SUM(t.Id) as TagSum,
    SUM(vt.Id) as VoteTypeSum,
    COUNT(CASE WHEN u.Reputation > 10000 THEN 1 END) as HighReputationUsers,
    COUNT(CASE WHEN p.Score > 100 THEN 1 END) as HighScorePosts,
    COUNT(CASE WHEN p.ViewCount > 5000 THEN 1 END) as HighViewPosts,
    COUNT(CASE WHEN p.AnswerCount > 10 THEN 1 END) as HighAnswerPosts,
    COUNT(CASE WHEN p.CommentCount > 5 THEN 1 END) as HighCommentPosts,
    COUNT(CASE WHEN p.FavoriteCount > 10 THEN 1 END) as HighFavoritePosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as QuestionPosts,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as AnswerPosts,
    COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 END) as ClosedPosts,
    COUNT(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 END) as CommunityOwnedPosts,
    COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) as AcceptedAnswerPosts,
    COUNT(CASE WHEN p.ParentId IS NOT NULL THEN 1 END) as AnswerToQuestionPosts,
    COUNT(CASE WHEN p.ParentId IS NULL THEN 1 END) as QuestionPostsOnly,
    COUNT(CASE WHEN u.EmailHash IS NOT NULL THEN 1 END) as UsersWithEmail,
    COUNT(CASE WHEN u.WebsiteUrl IS NOT NULL THEN 1 END) as UsersWithWebsite,
    COUNT(CASE WHEN u.Location IS NOT NULL THEN 1 END) as UsersWithLocation,
    COUNT(CASE WHEN u.AboutMe IS NOT NULL THEN 1 END) as UsersWithAbout,
    COUNT(CASE WHEN p.Tags IS NOT NULL THEN 1 END) as PostsWithTags,
    COUNT(CASE WHEN p.Body IS NOT NULL THEN 1 END) as PostsWithBody,
    COUNT(CASE WHEN c.Text IS NOT NULL THEN 1 END) as CommentsWithText,
    COUNT(CASE WHEN ph.Text IS NOT NULL THEN 1 END) as PostHistoriesWithText,
    COUNT(CASE WHEN pl.RelatedPostId IS NOT NULL THEN 1 END) as PostLinksWithRelated,
    COUNT(CASE WHEN t.ExcerptPostId IS NOT NULL THEN 1 END) as TagsWithExcerpt,
    COUNT(CASE WHEN t.WikiPostId IS NOT NULL THEN 1 END) as TagsWithWiki,
    COUNT(CASE WHEN b.Date IS NOT NULL THEN 1 END) as BadgesWithDate,
    COUNT(CASE WHEN ph.Comment IS NOT NULL THEN 1 END) as PostHistoriesWithComment,
    COUNT(CASE WHEN ph.RevisionGUID IS NOT NULL THEN 1 END) as PostHistoriesWithRevision,
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END as HasRecords,
    CASE WHEN COUNT(*) > 10000 THEN 'Large Dataset' ELSE 'Small Dataset' END as DatasetSize,
    (SELECT COUNT(DISTINCT UserId) FROM PostMetrics WHERE ScoreTier = 'Gold') as GoldTierUsers,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScoreTier = 'Gold') as GoldTierPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScoreTier IN ('Silver', 'Gold')) as SilverOrGoldPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE PopularityTier IN ('Viral', 'Popular')) as HighPopularityPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE DaysActive > 365) as LongActivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView > 0.5) as HighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > 100) as VeryAnsweredPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ViewCount > 10000) as VeryViewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE FavoriteCount > 100) as VeryFavoritedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE CommentCount > 100) as VeryCommentedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Status = 'Closed') as ClosedPostsCount,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Status = 'Community Owned') as CommunityOwnedCount,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Status = 'Active') as ActivePostsCount,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE ScoreRank <= 100) as TopScoringUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE ActivityRank <= 100) as TopActivityUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE ReputationDecile = 10) as TopDecileUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Elite') as EliteUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Veteran') as VeteranUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Experienced') as ExperiencedUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'Active') as ActiveUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE UserStatus = 'New') as NewUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 100000) as VeryHighEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 10000) as HighEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 1000) as MediumEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 100) as LowEffectiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore > 0) as PositiveScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore = 0) as ZeroScoreUsers,
    (SELECT COUNT(DISTINCT UserId) FROM UserActivityStats WHERE EffectiveScore < 0) as NegativeScoreUsers,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView > 1.0) as ExtremelyHighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView BETWEEN 0.5 AND 1.0) as VeryHighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView BETWEEN 0.2 AND 0.5) as HighValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView BETWEEN 0.05 AND 0.2) as AverageValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView < 0.05) as LowValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView IS NULL) as NullValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView = 0) as ZeroValuePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView > 0.5) as VeryHighAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView BETWEEN 0.1 AND 0.5) as HighAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView < 0.1) as LowAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView IS NULL) as NullAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > 0 AND ViewCount > 0) as AnsweredViewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount = 0 AND ViewCount > 0) as UnansweredViewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > 0 AND ViewCount = 0) as AnsweredUnviewedPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount = 0 AND ViewCount = 0) as UnansweredUnviewedPosts,
    (SELECT AVG(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) as AvgScorePerViewAll,
    (SELECT MIN(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) as MinScorePerViewAll,
    (SELECT MAX(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) as MaxScorePerViewAll,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView BETWEEN (SELECT AVG(ScorePerView) - STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) AND (SELECT AVG(ScorePerView) + STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as NormalRangePosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView > (SELECT AVG(ScorePerView) + 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as OutlierHighPosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView < (SELECT AVG(ScorePerView) - 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as OutlierLowPosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView BETWEEN (SELECT AVG(ScorePerView) + STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) AND (SELECT AVG(ScorePerView) + 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as HighRangePosts,
    (SELECT COUNT(*) FROM PostMetrics WHERE ScorePerView BETWEEN (SELECT AVG(ScorePerView) - 2*STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL) AND (SELECT AVG(ScorePerView) - STDDEV(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as LowRangePosts,
    (SELECT AVG(AnswerCount) FROM PostMetrics WHERE AnswerCount IS NOT NULL) as AvgAnswersAll,
    (SELECT AVG(ViewCount) FROM PostMetrics WHERE ViewCount IS NOT NULL) as AvgViewsAll,
    (SELECT AVG(Score) FROM PostMetrics WHERE Score IS NOT NULL) as AvgScoreAll,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswerCount > (SELECT AVG(AnswerCount) FROM PostMetrics WHERE AnswerCount IS NOT NULL)) as AboveAvgAnswerPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ViewCount > (SELECT AVG(ViewCount) FROM PostMetrics WHERE ViewCount IS NOT NULL)) as AboveAvgViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score > (SELECT AVG(Score) FROM PostMetrics WHERE Score IS NOT NULL)) as AboveAvgScorePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE DaysActive > (SELECT AVG(DaysActive) FROM PostMetrics WHERE DaysActive IS NOT NULL)) as AboveAvgActivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE ScorePerView > (SELECT AVG(ScorePerView) FROM PostMetrics WHERE ScorePerView IS NOT NULL)) as AboveAvgScorePerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE AnswersPerView > (SELECT AVG(AnswersPerView) FROM PostMetrics WHERE AnswersPerView IS NOT NULL)) as AboveAvgAnswersPerViewPosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score > 0 AND AnswerCount > 0 AND ViewCount > 0) as ActivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score = 0 AND AnswerCount = 0 AND ViewCount = 0) as InactivePosts,
    (SELECT COUNT(DISTINCT PostId) FROM PostMetrics WHERE Score > 0 OR AnswerCount > 0 OR ViewCount > 0) as PositivePosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON 1 = 1
LEFT JOIN VoteTypes vt ON 1 = 1
WHERE u.Id IS NOT NULL OR p.Id IS NOT NULL OR b.Id IS NOT NULL OR c.Id IS NOT NULL OR ph.Id IS NOT NULL OR pl.Id IS NOT NULL OR t.Id IS NOT NULL OR vt.Id IS NOT NULL
  AND (u.Id IS NOT NULL OR b.Id IS NOT NULL OR c.Id IS NOT NULL OR ph.Id IS NOT NULL OR pl.Id IS NOT NULL OR t.Id IS NOT NULL OR vt.Id IS NOT NULL)
  AND (
    (SELECT COUNT(*) FROM UserActivityStats WHERE ScoreRank <= 50) > 0
    OR (SELECT COUNT(*) FROM UserActivityStats WHERE ActivityRank <= 50) > 0
    OR (SELECT COUNT(*) FROM PostMetrics WHERE ScoreTier = 'Gold') > 0
    OR (SELECT COUNT(*) FROM PostMetrics WHERE PopularityTier IN ('Viral', 'Popular')) > 0
  )
  AND (p.PostTypeId IS NULL OR p.PostTypeId IN (1, 2))
  AND (p.Score IS NULL OR p.Score > -1000)
  AND (p.ViewCount IS NULL OR p.ViewCount >= 0)
  AND (p.AnswerCount IS NULL OR p.AnswerCount >= 0)
  AND (p.CommentCount IS NULL OR p.CommentCount >= 0)
  AND (p.FavoriteCount IS NULL OR p.FavoriteCount >= 0)
  AND (u.Reputation IS NULL OR u.Reputation >= 0)
  AND (u.Views IS NULL OR u.Views >= 0)
  AND (u.UpVotes IS NULL OR u.UpVotes >= 0)
  AND (u.DownVotes IS NULL OR u.DownVotes >= 0)
  AND (b.Id IS NULL OR b.Id > 0)
  AND (c.Id IS NULL OR c.Id > 0)
  AND (ph.Id IS NULL OR ph.Id > 0)
  AND (pl.Id IS NULL OR pl.Id > 0)
  AND (t.Id IS NULL OR t.Id > 0)
  AND (vt.Id IS NULL OR vt.Id > 0)
  AND (u.CreationDate IS NULL OR u.CreationDate > '2000-01-01')
  AND (p.CreationDate IS NULL OR p.CreationDate > '2000-01-01')
  AND (c.CreationDate IS NULL OR c.CreationDate > '2000-01-01')
  AND (ph.CreationDate IS NULL OR ph.CreationDate > '2000-01-01')
  AND (pl.CreationDate IS NULL OR pl.CreationDate > '2000-01-01')
  AND (
    (u.DisplayName IS NULL OR LENGTH(u.DisplayName) > 0)
    AND (p.Title IS NULL OR LENGTH(p.Title) > 0)
    AND (b.Name IS NULL OR LENGTH(b.Name) > 0)
    AND (t.TagName IS NULL OR LENGTH(t.TagName) > 0)
    AND (c.Text IS NULL OR LENGTH(c.Text) > 0)
    AND (ph.Text IS NULL OR LENGTH(ph.Text) > 0)
    AND (pl.RelatedPostId IS NULL OR pl.RelatedPostId > 0)
  )
  AND COALESCE(p.Score, 0) + COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) +
      COALESCE(p.CommentCount, 0) + COALESCE(p.FavoriteCount, 0) + COALESCE(u.Reputation, 0) +
      COALESCE(u.Views, 0) + COALESCE(u.UpVotes, 0) + COALESCE(u.DownVotes, 0) > -10000
HAVING COUNT(*) > 0;