-- {"query": "7900.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3247} 
WITH UserActivity AS (
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
        COUNT(DISTINCT v.Id) as VoteCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        MAX(v.CreationDate) as LastVoteDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationTier,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Moderately Active'
            ELSE 'Inactive'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalytics AS (
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
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Moderately Voted'
            WHEN p.Score > 0 THEN 'Slightly Voted'
            ELSE 'Neutral'
        END as VoteScoreCategory,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as RecentRank,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LAG(p.CreationDate) OVER (ORDER BY p.CreationDate) as PreviousDate,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingAvgScore,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount) as ViewDecile,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 
            0
        ) as CommentCountAdjusted
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ComplexUserStats AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.VoteCount,
        ua.LastPostDate,
        ua.LastCommentDate,
        ua.LastBadgeDate,
        ua.LastVoteDate,
        ua.ReputationTier,
        ua.ActivityLevel,
        CASE 
            WHEN ua.PostCount > 0 THEN CAST(ua.CommentCount AS FLOAT) / CAST(ua.PostCount AS FLOAT)
            ELSE 0.0
        END as CommentsPerPost,
        CASE 
            WHEN ua.BadgeCount > 0 THEN CAST(ua.VoteCount AS FLOAT) / CAST(ua.BadgeCount AS FLOAT)
            ELSE 0.0
        END as VotesPerBadge,
        DATEDIFF(day, ua.LastPostDate, CURRENT_TIMESTAMP) as DaysSinceLastPost,
        DATEDIFF(day, ua.LastCommentDate, CURRENT_TIMESTAMP) as DaysSinceLastComment,
        DATEDIFF(day, ua.LastBadgeDate, CURRENT_TIMESTAMP) as DaysSinceLastBadge,
        DATEDIFF(day, ua.LastVoteDate, CURRENT_TIMESTAMP) as DaysSinceLastVote,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC) as ReputationRank,
        AVG(ua.Reputation) OVER (PARTITION BY ua.ReputationTier ORDER BY ua.Reputation DESC) as TierAvgReputation,
        RANK() OVER (ORDER BY ua.PostCount DESC) as PostCountRank,
        PERCENT_RANK() OVER (ORDER BY ua.CommentCount) as CommentPercentile,
        CUME_DIST() OVER (ORDER BY ua.BadgeCount) as BadgeDistribution,
        NTILE(4) OVER (ORDER BY ua.Views) as ViewQuartile,
        LAG(ua.Reputation) OVER (ORDER BY ua.Reputation DESC) as PreviousReputation,
        LAG(ua.PostCount) OVER (ORDER BY ua.Reputation DESC) as PreviousPostCount,
        LEAD(ua.Reputation) OVER (ORDER BY ua.Reputation DESC) as NextReputation
    FROM UserActivity ua
),
CombinedResults AS (
    SELECT 
        cus.UserId,
        cus.DisplayName,
        cus.Reputation,
        cus.Views,
        cus.UpVotes,
        cus.DownVotes,
        cus.PostCount,
        cus.CommentCount,
        cus.BadgeCount,
        cus.VoteCount,
        cus.LastPostDate,
        cus.LastCommentDate,
        cus.LastBadgeDate,
        cus.LastVoteDate,
        cus.ReputationTier,
        cus.ActivityLevel,
        cus.CommentsPerPost,
        cus.VotesPerBadge,
        cus.DaysSinceLastPost,
        cus.DaysSinceLastComment,
        cus.DaysSinceLastBadge,
        cus.DaysSinceLastVote,
        cus.ReputationRank,
        cus.TierAvgReputation,
        cus.PostCountRank,
        cus.CommentPercentile,
        cus.BadgeDistribution,
        cus.ViewQuartile,
        cus.PreviousReputation,
        cus.PreviousPostCount,
        cus.NextReputation,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCountAdjusted,
        pa.FavoriteCount,
        pa.CreationDate,
        pa.LastActivityDate,
        pa.PostCategory,
        pa.VoteScoreCategory,
        pa.RecentRank,
        pa.PreviousScore,
        pa.PreviousDate,
        pa.MovingAvgScore,
        pa.ScoreRank,
        pa.ViewDecile,
        CASE 
            WHEN pa.ViewCount > 1000 AND pa.Score > 50 THEN 'Trending'
            WHEN pa.ViewCount > 500 AND pa.Score > 25 THEN 'Popular'
            WHEN pa.ViewCount > 100 AND pa.Score > 10 THEN 'Noticeable'
            ELSE 'Standard'
        END as TrendingStatus
    FROM ComplexUserStats cus
    LEFT JOIN PostAnalytics pa ON cus.UserId = pa.OwnerUserId
    WHERE cus.PostCount > 0
),
AggregatedStats AS (
    SELECT 
        cr.UserId,
        cr.DisplayName,
        cr.Reputation,
        cr.Views,
        cr.UpVotes,
        cr.DownVotes,
        cr.PostCount,
        cr.CommentCount,
        cr.BadgeCount,
        cr.VoteCount,
        cr.LastPostDate,
        cr.LastCommentDate,
        cr.LastBadgeDate,
        cr.LastVoteDate,
        cr.ReputationTier,
        cr.ActivityLevel,
        cr.CommentsPerPost,
        cr.VotesPerBadge,
        cr.DaysSinceLastPost,
        cr.DaysSinceLastComment,
        cr.DaysSinceLastBadge,
        cr.DaysSinceLastVote,
        cr.ReputationRank,
        cr.TierAvgReputation,
        cr.PostCountRank,
        cr.CommentPercentile,
        cr.BadgeDistribution,
        cr.ViewQuartile,
        cr.PreviousReputation,
        cr.PreviousPostCount,
        cr.NextReputation,
        cr.PostId,
        cr.Title,
        cr.Score,
        cr.ViewCount,
        cr.AnswerCount,
        cr.CommentCountAdjusted,
        cr.FavoriteCount,
        cr.CreationDate,
        cr.LastActivityDate,
        cr.PostCategory,
        cr.VoteScoreCategory,
        cr.RecentRank,
        cr.PreviousScore,
        cr.PreviousDate,
        cr.MovingAvgScore,
        cr.ScoreRank,
        cr.ViewDecile,
        cr.TrendingStatus,
        COUNT(*) OVER () as TotalUsers,
        MAX(cr.Reputation) OVER () as MaxReputation,
        MIN(cr.Reputation) OVER () as MinReputation,
        AVG(cr.Reputation) OVER () as AvgReputation,
        COUNT(DISTINCT cr.PostId) OVER () as TotalPosts,
        SUM(cr.Score) OVER () as TotalScore,
        AVG(cr.ViewCount) OVER () as AvgViewCount,
        SUM(cr.CommentCount) OVER () as TotalComments,
        SUM(cr.BadgeCount) OVER () as TotalBadges,
        SUM(cr.VoteCount) OVER () as TotalVotes,
        STRING_AGG(cr.Title, '; ') WITHIN GROUP (ORDER BY cr.CreationDate) as AllTitles,
        STRING_AGG(cr.Tags, '|') WITHIN GROUP (ORDER BY cr.CreationDate) as AllTags,
        CASE 
            WHEN cr.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
            WHEN cr.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
            ELSE 'Average'
        END as ReputationStatus,
        CASE 
            WHEN cr.TrendingStatus = 'Trending' THEN 'High Impact'
            WHEN cr.TrendingStatus = 'Popular' THEN 'Medium Impact'
            WHEN cr.TrendingStatus = 'Noticeable' THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END as ImpactLevel,
        ROW_NUMBER() OVER (ORDER BY cr.Score DESC, cr.ViewCount DESC) as OverallRank,
        DENSE_RANK() OVER (ORDER BY cr.ReputationTier, cr.PostCount DESC) as UserPerformanceRank,
        PERCENT_RANK() OVER (ORDER BY cr.Score) as ScorePercentile,
        CUME_DIST() OVER (ORDER BY cr.ViewCount) as ViewPercentile
    FROM CombinedResults cr
)
SELECT 
    ar.UserId,
    ar.DisplayName,
    ar.Reputation,
    ar.Views,
    ar.UpVotes,
    ar.DownVotes,
    ar.PostCount,
    ar.CommentCount,
    ar.BadgeCount,
    ar.VoteCount,
    ar.LastPostDate,
    ar.LastCommentDate,
    ar.LastBadgeDate,
    ar.LastVoteDate,
    ar.ReputationTier,
    ar.ActivityLevel,
    ar.CommentsPerPost,
    ar.VotesPerBadge,
    ar.DaysSinceLastPost,
    ar.DaysSinceLastComment,
    ar.DaysSinceLastBadge,
    ar.DaysSinceLastVote,
    ar.ReputationRank,
    ar.TierAvgReputation,
    ar.PostCountRank,
    ar.CommentPercentile,
    ar.BadgeDistribution,
    ar.ViewQuartile,
    ar.PreviousReputation,
    ar.PreviousPostCount,
    ar.NextReputation,
    ar.PostId,
    ar.Title,
    ar.Score,
    ar.ViewCount,
    ar.AnswerCount,
    ar.CommentCountAdjusted,
    ar.FavoriteCount,
    ar.CreationDate,
    ar.LastActivityDate,
    ar.PostCategory,
    ar.VoteScoreCategory,
    ar.RecentRank,
    ar.PreviousScore,
    ar.PreviousDate,
    ar.MovingAvgScore,
    ar.ScoreRank,
    ar.ViewDecile,
    ar.TrendingStatus,
    ar.TotalUsers,
    ar.MaxReputation,
    ar.MinReputation,
    ar.AvgReputation,
    ar.TotalPosts,
    ar.TotalScore,
    ar.AvgViewCount,
    ar.TotalComments,
    ar.TotalBadges,
    ar.TotalVotes,
    ar.AllTitles,
    ar.AllTags,
    ar.ReputationStatus,
    ar.ImpactLevel,
    ar.OverallRank,
    ar.UserPerformanceRank,
    ar.ScorePercentile,
    ar.ViewPercentile,
    CASE 
        WHEN ar.PostCategory = 'Question with Accepted Answer' AND ar.Score > 10 THEN 'Excellent Question'
        WHEN ar.PostCategory = 'Answer' AND ar.Score > 10 THEN 'Excellent Answer'
        WHEN ar.PostCategory = 'Question with Accepted Answer' THEN 'Good Question'
        WHEN ar.PostCategory = 'Answer' THEN 'Good Answer'
        ELSE 'Standard Post'
    END as PostQuality,
    CASE 
        WHEN ar.PostCategory = 'Question with Accepted Answer' AND ar.CommentCountAdjusted > 5 THEN 'Highly Engaged Question'
        WHEN ar.PostCategory = 'Answer' AND ar.CommentCountAdjusted > 3 THEN 'Highly Engaged Answer'
        WHEN ar.PostCategory = 'Question with Accepted Answer' THEN 'Moderately Engaged Question'
        WHEN ar.PostCategory = 'Answer' THEN 'Moderately Engaged Answer'
        ELSE 'Low Engagement'
    END as EngagementLevel,
    CASE 
        WHEN ar.TrendingStatus = 'Trending' AND ar.Reputation > 5000 THEN 'Viral High Performer'
        WHEN ar.TrendingStatus = 'Trending' THEN 'Viral Contributor'
        WHEN ar.TrendingStatus = 'Popular' AND ar.Reputation > 5000 THEN 'Popular High Performer'
        WHEN ar.TrendingStatus = 'Popular' THEN 'Popular Contributor'
        ELSE 'Standard Contributor'
    END as ContributorTier,
    ROW_NUMBER() OVER (PARTITION BY ar.ReputationTier ORDER BY ar.Score DESC) as TierScoreRank,
    RANK() OVER (PARTITION BY ar.ActivityLevel ORDER BY ar.ViewCount DESC) as ActivityViewRank,
    DENSE_RANK() OVER (ORDER BY ar.ViewCount DESC, ar.Score DESC) as ContentPopularityRank
FROM AggregatedStats ar
WHERE ar.Reputation > 100 
   AND ar.PostCount > 1 
   AND (ar.Score > 0 OR ar.ViewCount > 0)
   AND (ar.BadgeCount > 0 OR ar.VoteCount > 0)
   AND EXISTS (
       SELECT 1 
       FROM Posts p 
       WHERE p.OwnerUserId = ar.UserId 
         AND p.CreationDate > DATEADD(year, -1, CURRENT_TIMESTAMP)
   )
   AND NOT EXISTS (
       SELECT 1 
       FROM Users u 
       WHERE u.Id = ar.UserId 
         AND u.DisplayName IS NULL
   )
   AND ar.Title IS NOT NULL
   AND ar.Title != ''
   AND ar.Tags IS NOT NULL
ORDER BY 
    ar.Score DESC,
    ar.ViewCount DESC,
    ar.PostCount DESC,
    ar.Reputation DESC,
    ar.OverallRank ASC
OFFSET 1000 ROWS
FETCH NEXT 1000 ROWS ONLY;