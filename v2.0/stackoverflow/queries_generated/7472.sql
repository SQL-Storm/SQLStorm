-- {"query": "7472.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2843} 
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
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation < 100 THEN 'Novice'
            WHEN u.Reputation < 1000 THEN 'Intermediate'
            WHEN u.Reputation < 10000 THEN 'Advanced'
            ELSE 'Expert'
        END as ReputationLevel,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) THEN 'QuestionAuthor'
            WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) THEN 'AnswerAuthor'
            ELSE 'Neither'
        END as UserRole,
        STRING_AGG(DISTINCT t.TagName, ', ') as FavoriteTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Tags t ON t.Id IN (
        SELECT Id FROM Tags WHERE TagName IN (
            SELECT DISTINCT UNNEST(STRING_TO_ARRAY(p.Tags, '><')) 
            FROM Posts p 
            WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL AND p.Tags != ''
        )
    )
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostSummary AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.Score, 0) as Score,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankWithinType,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as RecentPostRank,
        DENSE_RANK() OVER (ORDER BY p.OwnerUserId) as UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'::timestamp
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.Id END) as TitleEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.Id END) as BodyEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) as ClosedPosts,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END) as ReopenedPosts,
        MAX(ph.CreationDate) as LastActivityDate,
        AGE(MAX(ph.CreationDate), MIN(ph.CreationDate)) as ActivityDuration
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.CreationDate >= '2020-01-01'::timestamp
    GROUP BY u.Id, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagRequirement,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END as TagAccess,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t.Count) as MedianTagCount,
        AVG(t.Count) as AvgTagCount,
        STDDEV(t.Count) as StdDevTagCount
    FROM Tags t
    WHERE t.Count > 0
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsRequired, t.IsModeratorOnly
),
ComplexPostAnalysis AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.OwnerUserId,
        ps.PostType,
        ps.ScoreRankWithinType,
        ps.RecentPostRank,
        ps.UserPostRank,
        ps.ScorePercentile,
        ps.AnswerCount,
        ps.CommentCount,
        ps.Tags,
        ps.Score - COALESCE(ps.PreviousScore, 0) as ScoreChangeFromPrevious,
        ps.Score - COALESCE(ps.NextScore, 0) as ScoreChangeFromNext,
        ps.Score - ps.AvgScoreByType as ScoreDeviationFromAvg,
        CASE 
            WHEN ps.Score > 100 THEN 'HighlyVoted'
            WHEN ps.Score > 20 THEN 'ModeratelyVoted'
            WHEN ps.Score > 5 THEN 'LowVoted'
            ELSE 'VeryLowVoted'
        END as VoteCategory,
        CASE 
            WHEN ps.AnswerCount > 5 THEN 'WellAnswered'
            WHEN ps.AnswerCount > 1 THEN 'Answered'
            ELSE 'Unanswered'
        END as AnswerStatus,
        CASE 
            WHEN ps.CommentCount > 10 THEN 'HighlyCommented'
            WHEN ps.CommentCount > 3 THEN 'ModeratelyCommented'
            ELSE 'LowCommented'
        END as CommentStatus,
        CASE 
            WHEN ps.ViewCount > 1000 THEN 'Popular'
            WHEN ps.ViewCount > 100 THEN 'Moderate'
            ELSE 'LowView'
        END as PopularityLevel,
        COALESCE(SUBSTRING(ps.Tags, 2, LENGTH(ps.Tags)-2), 'No Tags') as CleanTags
    FROM PostSummary ps
    WHERE ps.PostType IN ('Question', 'Answer')
),
CombinedAnalysis AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.PostCount,
        u.CommentCount,
        u.BadgeCount,
        u.ReputationLevel,
        u.UserRole,
        u.FavoriteTags,
        COALESCE(pa.Score, 0) as LatestPostScore,
        COALESCE(pa.ViewCount, 0) as LatestPostViews,
        COALESCE(pa.AnswerCount, 0) as LatestPostAnswers,
        COALESCE(pa.CommentCount, 0) as LatestPostComments,
        pa.PostType,
        pa.ScoreRankWithinType,
        pa.RecentPostRank,
        pa.ScoreDeviationFromAvg,
        pa.VoteCategory,
        pa.AnswerStatus,
        pa.CommentStatus,
        pa.PopularityLevel,
        pa.CleanTags,
        COALESCE(ua.HistoryCount, 0) as TotalHistory,
        COALESCE(ua.TitleEdits, 0) as TitleEdits,
        COALESCE(ua.BodyEdits, 0) as BodyEdits,
        COALESCE(ua.ClosedPosts, 0) as ClosedPosts,
        COALESCE(ua.ReopenedPosts, 0) as ReopenedPosts,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM PostSummary) THEN 'AboveAvg'
            WHEN pa.Score > (SELECT AVG(Score) FROM PostSummary WHERE PostType = 'Question') THEN 'QuestionAboveAvg'
            ELSE 'BelowAvg'
        END as PerformanceLevel,
        RANK() OVER (ORDER BY pa.Score DESC) as GlobalScoreRank,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        ROW_NUMBER() OVER (ORDER BY u.Views DESC) as ViewRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'TopTier'
            WHEN u.Reputation >= 1000 THEN 'MidTier'
            ELSE 'Beginner'
        END as TierStatus,
        LENGTH(u.FavoriteTags) as FavoriteTagsLength,
        ABS(pa.ScoreChangeFromPrevious) as MaxScoreChangeFromPrev,
        ABS(pa.ScoreChangeFromNext) as MaxScoreChangeFromNext
    FROM UserStats u
    LEFT JOIN ComplexPostAnalysis pa ON u.UserId = pa.OwnerUserId
    LEFT JOIN UserActivity ua ON u.UserId = ua.UserId
    WHERE u.PostCount > 0
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.Views,
    ca.PostCount,
    ca.CommentCount,
    ca.BadgeCount,
    ca.ReputationLevel,
    ca.UserRole,
    ca.FavoriteTags,
    ca.LatestPostScore,
    ca.LatestPostViews,
    ca.LatestPostAnswers,
    ca.LatestPostComments,
    ca.PostType,
    ca.ScoreRankWithinType,
    ca.RecentPostRank,
    ca.ScoreDeviationFromAvg,
    ca.VoteCategory,
    ca.AnswerStatus,
    ca.CommentStatus,
    ca.PopularityLevel,
    ca.CleanTags,
    ca.TotalHistory,
    ca.TitleEdits,
    ca.BodyEdits,
    ca.ClosedPosts,
    ca.ReopenedPosts,
    ca.PerformanceLevel,
    ca.GlobalScoreRank,
    ca.ReputationRank,
    ca.ViewRank,
    ca.TierStatus,
    ca.FavoriteTagsLength,
    ca.MaxScoreChangeFromPrev,
    ca.MaxScoreChangeFromNext,
    
    -- Aggregated calculated metrics
    (ca.ScoreDeviationFromAvg / NULLIF(ca.GlobalScoreRank, 0)) as NormalizedDeviation,
    (ca.Reputation * 1.0 / NULLIF(ca.PostCount, 0)) as ReputationPerPost,
    (ca.CommentCount * 1.0 / NULLIF(ca.PostCount, 0)) as CommentsPerPost,
    (ca.BadgeCount * 1.0 / NULLIF(ca.Views, 0)) as BadgesPerView,
    
    -- Complex string operations
    CONCAT(
        CASE WHEN ca.UserRole = 'QuestionAuthor' THEN 'QA' ELSE '' END,
        CASE WHEN ca.UserRole = 'AnswerAuthor' THEN 'AA' ELSE '' END,
        CASE WHEN ca.ReputationLevel = 'Expert' THEN 'EX' ELSE '' END,
        CASE WHEN ca.ReputationLevel = 'Advanced' THEN 'AD' ELSE '' END
    ) as UserTag,
    
    -- Conditional expressions based on multiple criteria
    CASE 
        WHEN ca.Reputation > 1000 AND ca.PostCount > 50 AND ca.BadgeCount > 20 THEN 'ActiveExpert'
        WHEN ca.Reputation > 500 AND ca.PostCount > 20 AND ca.BadgeCount > 10 THEN 'ActiveContributor'
        WHEN ca.Reputation > 100 AND ca.PostCount > 5 THEN 'RegularUser'
        ELSE 'NewUser'
    END as UserEngagementStatus,
    
    -- Window function applied to string data
    FIRST_VALUE(ca.DisplayName) OVER (
        PARTITION BY ca.ReputationLevel 
        ORDER BY ca.PostCount DESC
    ) as TopPostCountUserByReputationLevel,
    
    -- Set operators simulation with subqueries
    EXISTS(
        SELECT 1 FROM Badges b 
        WHERE b.UserId = ca.UserId AND b.Class = 1
    ) as HasGoldBadge,
    
    -- Correlated subqueries and complex calculations
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2) as AnswerCount,
    
    -- String and date manipulation
    SUBSTRING(ca.DisplayName, 1, 1) || '.' || SUBSTRING(ca.DisplayName, POSITION(' ' IN ca.DisplayName) + 1, 1) as NameInitials,
    EXTRACT(YEAR FROM ca.LastPostDate) as LastPostYear,
    DATE_TRUNC('month', ca.LastPostDate) as LastPostMonth,
    
    -- NULL-safe operations
    COALESCE(NULLIF(ca.FavoriteTags, ''), 'No Preferred Tags') as DefaultTags
    
FROM CombinedAnalysis ca
WHERE ca.Reputation > 10
    AND ca.PostCount > 0
    AND (ca.UserRole = 'QuestionAuthor' OR ca.UserRole = 'AnswerAuthor')
ORDER BY 
    ca.Reputation DESC,
    ca.PostCount DESC,
    ca.ReputationRank ASC
LIMIT 10000;