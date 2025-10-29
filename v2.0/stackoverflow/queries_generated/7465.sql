-- {"query": "7465.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2384} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate)) as DaysSinceLastPost,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        PERCENT_RANK() OVER (ORDER BY u.Reputation DESC) as RepPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' AND u.CreationDate < '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
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
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as HasAcceptedAnswer,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as DaysOld,
        COALESCE(p.Score, 0) + COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) as EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as OwnerPostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgOwnerScore,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreDecile
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01' 
      AND p.CreationDate < '2023-01-01'
      AND p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagType,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END as AccessLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as TagPopularityRank,
        PERCENT_RANK() OVER (ORDER BY t.Count DESC) as TagPopularityPercentile
    FROM Tags t
    WHERE t.Count > 100
),
UserActivityWithBadges AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.UpVotes,
        uas.DownVotes,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        uas.DaysSinceLastPost,
        uas.PostRank,
        uas.RepPercentile,
        COUNT(DISTINCT CASE WHEN b.Name IN ('Beta', 'Pioneer', 'Stellar', 'Necromancer', 'Electorate') THEN b.Id END) as EliteBadges,
        CASE WHEN uas.Badges > 50 THEN 'Elite' 
             WHEN uas.Badges > 20 THEN 'Veteran' 
             WHEN uas.Badges > 5 THEN 'Regular' 
             ELSE 'Newbie' END as BadgeStatus,
        CASE WHEN uas.TotalPosts > 1000 THEN 'Legendary'
             WHEN uas.TotalPosts > 500 THEN 'Master'
             WHEN uas.TotalPosts > 100 THEN 'Expert'
             ELSE 'Beginner' END as PostingLevel
    FROM UserActivityStats uas
    LEFT JOIN Badges b ON uas.UserId = b.UserId
    GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.Views, uas.UpVotes, uas.DownVotes, 
             uas.TotalPosts, uas.Questions, uas.Answers, uas.Comments, uas.Badges, 
             uas.LastPostDate, uas.DaysSinceLastPost, uas.PostRank, uas.RepPercentile
),
PostWithRelated AS (
    SELECT 
        ph.PostId,
        ph.CreationDate as HistoryDate,
        ph.UserId,
        ph.PostHistoryTypeId,
        p.Title as PostTitle,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ph.UserDisplayName,
        ph.Text,
        ph.Comment,
        u.DisplayName as OwnerDisplayName,
        CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36, 66) 
             THEN COALESCE(ph.Comment, 'No Comment') 
             ELSE COALESCE(ph.Text, 'No Text') END as HistoryDetails,
        (SELECT AVG(v.Score) FROM Votes v WHERE v.PostId = ph.PostId) as AvgVoteScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ph.PostId) as CommentCount,
        CASE WHEN ph.PostHistoryTypeId = 10 THEN 
            COALESCE(CAST(ph.Comment AS INT), 0)
            ELSE 0 END as CloseReasonId,
        CASE WHEN ph.PostHistoryTypeId = 10 THEN 
            (SELECT Name FROM CloseReasonTypes crt WHERE crt.Id = CAST(ph.Comment AS INT))
            ELSE NULL END as CloseReasonName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as RecentHistory,
        DENSE_RANK() OVER (ORDER BY ph.CreationDate DESC) as HistoryRank
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE ph.CreationDate >= '2018-01-01'
      AND ph.CreationDate < '2023-01-01'
)
SELECT 
    'Combined Performance Analysis' as AnalysisType,
    COUNT(DISTINCT uab.UserId) as ActiveUsers,
    COUNT(DISTINCT pp.PostId) as ActivePosts,
    COUNT(DISTINCT ta.TagName) as PopularTags,
    COUNT(DISTINCT pwr.PostId) as PostHistoryRecords,
    AVG(uab.Reputation) as AvgReputation,
    SUM(uab.TotalPosts) as TotalUserPosts,
    AVG(pp.Score) as AvgPostScore,
    AVG(ta.TagCount) as AvgTagCount,
    SUM(pp.ViewCount) as TotalViews,
    AVG(uab.Badges) as AvgBadgesPerUser,
    COUNT(DISTINCT CASE WHEN uab.BadgeStatus = 'Elite' THEN uab.UserId END) as EliteUsers,
    COUNT(DISTINCT CASE WHEN uab.PostingLevel = 'Legendary' THEN uab.UserId END) as LegendaryPosters,
    COUNT(DISTINCT CASE WHEN pp.Score > 1000 THEN pp.PostId END) as HighScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01') as RecentQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.CreationDate >= '2020-01-01') as RecentAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.IsClosed = 1 AND p.CreationDate >= '2020-01-01') as RecentlyClosed,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 10 AND ph.CreationDate >= '2020-01-01') as CloseVotes,
    (SELECT MIN(HistoryDate) FROM PostWithRelated) as EarliestHistoryRecord,
    (SELECT MAX(HistoryDate) FROM PostWithRelated) as LatestHistoryRecord,
    COUNT(DISTINCT CASE WHEN uab.RepPercentile > 0.9 THEN uab.UserId END) as Top10PercentReputation,
    COUNT(DISTINCT CASE WHEN pp.EngagementScore > 1000 THEN pp.PostId END) as HighEngagementPosts,
    AVG(DATEDIFF(CURRENT_TIMESTAMP, pp.CreationDate)) as AvgDaysOld,
    (SELECT COUNT(*) FROM Posts p WHERE p.ViewCount > 10000) as HighlyViewedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.AnswerCount > 100) as HighlyAnsweredPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.CommentCount > 10) as HighlyCommentedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.FavoriteCount > 5) as HighlyFavoritedPosts,
    COUNT(DISTINCT CASE WHEN uab.PostRank = 1 THEN uab.UserId END) as TopPosters,
    (SELECT AVG(EngagementScore) FROM PostPerformance) as AvgEngagementScore,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostHistoryTypeId = 17 OR ph.PostHistoryTypeId = 35 OR ph.PostHistoryTypeId = 36) as MigrationRecords,
    (SELECT COUNT(*) FROM Tags t WHERE t.Count > 1000) as HighlyPopulatedTags,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM Posts p WHERE p.ContentLicense != 'CC BY-SA 4.0' AND p.ContentLicense IS NOT NULL) as NonStandardLicensePosts
FROM UserActivityWithBadges uab
FULL OUTER JOIN PostPerformance pp ON uab.UserId = pp.OwnerUserId
FULL OUTER JOIN TagAnalysis ta ON uab.UserId = ta.TagName
FULL OUTER JOIN PostWithRelated pwr ON uab.UserId = pwr.UserId
WHERE (uab.UserId IS NOT NULL OR pp.PostId IS NOT NULL OR ta.TagName IS NOT NULL OR pwr.PostId IS NOT NULL)
GROUP BY 'Combined Performance Analysis'