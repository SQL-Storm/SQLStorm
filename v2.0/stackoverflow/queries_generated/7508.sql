-- {"query": "7508.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 7087} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as moving_avg_score
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Obscure'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count as count_diff_from_prev
    FROM Tags t
    WHERE t.Count > 0
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ClosedDate,
        rp.rn,
        rp.prev_score,
        rp.moving_avg_score,
        CASE 
            WHEN rp.Score > COALESCE(rp.prev_score, 0) THEN 'Increased'
            WHEN rp.Score < COALESCE(rp.prev_score, 0) THEN 'Decreased'
            ELSE 'No Change'
        END as ScoreChange,
        CASE 
            WHEN rp.Score > 100 THEN 'High Impact'
            WHEN rp.Score > 50 THEN 'Medium Impact'
            WHEN rp.Score > 10 THEN 'Low Impact'
            ELSE 'Minimal Impact'
        END as ImpactLevel,
        COALESCE(rp.AnswerCount, 0) + COALESCE(rp.CommentCount, 0) as EngagementCount,
        CASE 
            WHEN rp.FavoriteCount > 5 THEN 'Favored'
            WHEN rp.FavoriteCount > 1 THEN 'Moderately Favored'
            ELSE 'Not Favored'
        END as FavoriteStatus,
        (rp.Score * COALESCE(rp.ViewCount, 1)) as ScoreViewProduct,
        ABS(COALESCE(rp.prev_score, 0) - rp.Score) as ScoreChangeMagnitude,
        EXTRACT(YEAR FROM rp.CreationDate) as PostYear,
        EXTRACT(MONTH FROM rp.CreationDate) as PostMonth,
        (rp.Score - rp.moving_avg_score) / NULLIF(rp.moving_avg_score, 0) * 100 as ScoreVsAvgPercent
    FROM RankedPosts rp
    WHERE rp.rn <= 5
),
CombinedAnalysis AS (
    SELECT 
        cpa.Id,
        cpa.PostTypeId,
        cpa.Score,
        cpa.ViewCount,
        cpa.CreationDate,
        cpa.OwnerUserId,
        cpa.Title,
        cpa.Tags,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.ClosedDate,
        cpa.rn,
        cpa.prev_score,
        cpa.moving_avg_score,
        cpa.ScoreChange,
        cpa.ImpactLevel,
        cpa.EngagementCount,
        cpa.FavoriteStatus,
        cpa.ScoreViewProduct,
        cpa.ScoreChangeMagnitude,
        cpa.PostYear,
        cpa.PostMonth,
        cpa.ScoreVsAvgPercent,
        us.Reputation,
        us.DisplayName,
        us.Views,
        us.UpVotes,
        us.DownVotes,
        us.PostCount,
        us.BadgeCount,
        us.CommentCount as UserCommentCount,
        us.LastPostDate,
        us.ReputationLevel,
        us.AllTags,
        ta.TagName,
        ta.Count as TagCount,
        ta.ExcerptPostId,
        ta.WikiPostId,
        ta.PopularityLevel,
        ta.popularity_rank,
        ta.count_diff_from_prev,
        CASE 
            WHEN cpa.Score > 100 AND cpa.ViewCount > 1000 AND cpa.AnswerCount > 10 THEN 'Highly Popular'
            WHEN cpa.Score > 50 AND cpa.ViewCount > 500 THEN 'Popular'
            WHEN cpa.Score > 25 OR cpa.ViewCount > 250 THEN 'Moderate'
            ELSE 'Low'
        END as PostPopularity,
        CASE 
            WHEN cpa.PostTypeId = 1 AND cpa.Score > 10 AND cpa.AnswerCount > 0 THEN 'Active Question'
            WHEN cpa.PostTypeId = 2 AND cpa.Score > 5 THEN 'Active Answer'
            ELSE 'Inactive'
        END as PostActivityStatus,
        CASE 
            WHEN cpa.Score > 200 THEN 'Viral Potential'
            WHEN cpa.Score > 100 THEN 'Strong Potential'
            WHEN cpa.Score > 50 THEN 'Moderate Potential'
            ELSE 'Low Potential'
        END as PotentialCategory,
        (cpa.Score - cpa.prev_score) / NULLIF(cpa.prev_score, 0) * 100 as ScoreChangePercent,
        ABS(cpa.Score - (SELECT AVG(Score) FROM Posts WHERE PostTypeId = cpa.PostTypeId)) as ScoreDeviationFromAvg,
        DATEDIFF(CURRENT_DATE, cpa.CreationDate) as DaysSinceCreation,
        COALESCE(cpa.ClosedDate, '1900-01-01') = '1900-01-01' as IsOpen,
        CASE 
            WHEN (cpa.Score > 100 OR cpa.ViewCount > 1000) AND cpa.FavoriteCount > 5 THEN 'Trending'
            WHEN (cpa.Score > 50 OR cpa.ViewCount > 500) AND cpa.FavoriteCount > 2 THEN 'Popular'
            ELSE 'Regular'
        END as TrendingStatus,
        (cpa.AnswerCount * 10 + cpa.CommentCount * 5 + cpa.FavoriteCount * 20) as EngagementScore,
        CASE 
            WHEN cpa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above_Question_Avg'
            WHEN cpa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'Above_Answer_Avg'
            ELSE 'Below_Avg'
        END as ScoreComparison,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = cpa.Id AND p2.PostTypeId = 2) as ChildAnswerCount,
        (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = cpa.Id) as CommentCountForPost,
        (SELECT AVG(v.Score) FROM Votes v WHERE v.PostId = cpa.Id AND v.VoteTypeId IN (2, 3)) as AvgVoteScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cpa.Id AND v.VoteTypeId = 5) as FavoriteCountByVotes,
        CASE 
            WHEN cpa.PostTypeId = 1 AND cpa.AnswerCount = 0 THEN 'Unanswered_Question'
            WHEN cpa.PostTypeId = 2 AND cpa.Score < 0 THEN 'Low_Value_Answer'
            ELSE 'Normal'
        END as QuestionAnswerStatus,
        (cpa.Score * 0.5 + cpa.ViewCount * 0.3 + cpa.AnswerCount * 0.2) as CompositeScore,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = cpa.OwnerUserId AND b.Name LIKE '%Gold%') as GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = cpa.OwnerUserId AND b.Name LIKE '%Silver%') as SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = cpa.OwnerUserId AND b.Name LIKE '%Bronze%') as BronzeBadgeCount
    FROM ComplexPostAnalysis cpa
    LEFT JOIN UserStats us ON cpa.OwnerUserId = us.UserId
    LEFT JOIN TagAnalysis ta ON cpa.Tags LIKE '%' || ta.TagName || '%'
    WHERE cpa.Score IS NOT NULL 
)
SELECT 
    ca.Id,
    ca.PostTypeId,
    ca.Score,
    ca.ViewCount,
    ca.CreationDate,
    ca.OwnerUserId,
    ca.Title,
    ca.Tags,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.ClosedDate,
    ca.rn,
    ca.prev_score,
    ca.moving_avg_score,
    ca.ScoreChange,
    ca.ImpactLevel,
    ca.EngagementCount,
    ca.FavoriteStatus,
    ca.ScoreViewProduct,
    ca.ScoreChangeMagnitude,
    ca.PostYear,
    ca.PostMonth,
    ca.ScoreVsAvgPercent,
    ca.Reputation,
    ca.DisplayName,
    ca.Views,
    ca.UpVotes,
    ca.DownVotes,
    ca.PostCount,
    ca.BadgeCount,
    ca.UserCommentCount,
    ca.LastPostDate,
    ca.ReputationLevel,
    ca.AllTags,
    ca.TagName,
    ca.TagCount,
    ca.ExcerptPostId,
    ca.WikiPostId,
    ca.PopularityLevel,
    ca.popularity_rank,
    ca.count_diff_from_prev,
    ca.PostPopularity,
    ca.PostActivityStatus,
    ca.PotentialCategory,
    ca.ScoreChangePercent,
    ca.ScoreDeviationFromAvg,
    ca.DaysSinceCreation,
    ca.IsOpen,
    ca.TrendingStatus,
    ca.EngagementScore,
    ca.ScoreComparison,
    ca.ChildAnswerCount,
    ca.CommentCountForPost,
    ca.AvgVoteScore,
    ca.FavoriteCountByVotes,
    ca.QuestionAnswerStatus,
    ca.CompositeScore,
    ca.GoldBadgeCount,
    ca.SilverBadgeCount,
    ca.BronzeBadgeCount,
    CASE 
        WHEN ca.Score > 200 AND ca.ViewCount > 2000 AND ca.FavoriteCount > 10 THEN 'Viral_Success'
        WHEN ca.Score > 150 AND ca.ViewCount > 1500 THEN 'Success'
        WHEN ca.Score > 100 THEN 'Good'
        WHEN ca.Score > 50 THEN 'Fair'
        WHEN ca.Score > 10 THEN 'Poor'
        ELSE 'Very_Poor'
    END as PerformanceCategory,
    ROW_NUMBER() OVER (ORDER BY ca.Score DESC, ca.ViewCount DESC) as OverallRank,
    RANK() OVER (PARTITION BY ca.PostTypeId ORDER BY ca.Score DESC) as TypeRank,
    DENSE_RANK() OVER (ORDER BY ca.Reputation DESC) as ReputationRank,
    NTILE(10) OVER (ORDER BY ca.Score) as ScoreDecile,
    PERCENT_RANK() OVER (ORDER BY ca.ViewCount DESC) as ViewPercentile,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = ca.OwnerUserId AND p3.PostTypeId = 1) as OwnerQuestionCount,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = ca.OwnerUserId AND p4.PostTypeId = 2) as OwnerAnswerCount,
    (SELECT AVG(Score) FROM Posts p5 WHERE p5.OwnerUserId = ca.OwnerUserId AND p5.PostTypeId = 1) as OwnerAvgQuestionScore,
    (SELECT AVG(Score) FROM Posts p6 WHERE p6.OwnerUserId = ca.OwnerUserId AND p6.PostTypeId = 2) as OwnerAvgAnswerScore,
    MAX(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerMaxScore,
    MIN(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerMinScore,
    AVG(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerAvgScore,
    SUM(ca.ViewCount) OVER (PARTITION BY ca.OwnerUserId) as OwnerTotalViews,
    STDDEV(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerScoreStdDev,
    COUNT(*) OVER (PARTITION BY ca.OwnerUserId) as OwnerPostCount,
    CASE 
        WHEN ca.OwnerAvgQuestionScore > 50 THEN 'Active_Questioner'
        WHEN ca.OwnerAvgAnswerScore > 25 THEN 'Active_Answerer'
        ELSE 'Passive_User'
    END as UserActivityLevel,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.OwnerUserId AND v.VoteTypeId = 2) as OwnerUpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.OwnerUserId AND v.VoteTypeId = 3) as OwnerDownVotes,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = ca.OwnerUserId AND v.VoteTypeId = 8) as OwnerTotalBounty,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ca.OwnerUserId AND c.CreationDate >= ca.CreationDate - INTERVAL '30 days') as RecentComments,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.OwnerUserId AND b.Date >= ca.CreationDate - INTERVAL '30 days') as RecentBadges,
    CASE 
        WHEN ca.PostTypeId = 1 AND ca.Score > 100 AND ca.AnswerCount > 5 THEN 'Highly_Questioned'
        WHEN ca.PostTypeId = 2 AND ca.Score > 50 THEN 'Highly_Valued_Answer'
        ELSE 'Ordinary_Post'
    END as PostClassification,
    NULLIF(ca.Score, 0) as SafeScore,
    COALESCE(ca.Tags, '') as SafeTags,
    (ca.Score + ca.ViewCount + ca.AnswerCount + ca.CommentCount + ca.FavoriteCount) as TotalActivityIndicator,
    CASE 
        WHEN ca.ScoreChange = 'Increased' AND ca.Score > 0 THEN 'Growing_Importance'
        WHEN ca.ScoreChange = 'Decreased' AND ca.Score < 0 THEN 'Declining_Importance'
        ELSE 'Stable_Importance'
    END as ImportanceTrend,
    CASE 
        WHEN ca.ImpactLevel = 'High Impact' AND ca.FavoriteStatus = 'Favored' THEN 'Highly_Boosted'
        WHEN ca.ImpactLevel = 'Medium Impact' AND ca.FavoriteStatus = 'Favored' THEN 'Moderately_Boosted'
        ELSE 'Regular'
    END as BoostingStatus,
    (SELECT COUNT(*) FROM Posts p7 WHERE p7.ParentId = ca.Id AND p7.CreationDate >= ca.CreationDate + INTERVAL '1 day') as ImmediateAnswers,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = ca.Id AND ph.PostHistoryTypeId IN (2, 5, 10, 11, 12, 13, 16, 17, 18, 19, 20, 22, 24) AND ph.CreationDate >= ca.CreationDate) as EditCount,
    LAG(ca.Score) OVER (ORDER BY ca.CreationDate) as PrevScore,
    LEAD(ca.Score) OVER (ORDER BY ca.CreationDate) as NextScore,
    FIRST_VALUE(ca.Score) OVER (ORDER BY ca.CreationDate) as FirstScore,
    LAST_VALUE(ca.Score) OVER (ORDER BY ca.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as LastScore,
    NTH_VALUE(ca.Score, 3) OVER (ORDER BY ca.CreationDate) as ThirdScore,
    ROW_NUMBER() OVER (ORDER BY ca.ViewCount DESC) - ROW_NUMBER() OVER (ORDER BY ca.Score DESC) as ViewScoreRankGap,
    LAG(ca.ViewCount) OVER (ORDER BY ca.CreationDate) - ca.ViewCount as ViewChange,
    LEAD(ca.ViewCount) OVER (ORDER BY ca.CreationDate) - ca.ViewCount as NextViewChange,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p8 WHERE p8.ParentId = ca.Id AND p8.Score > 100) THEN 'Has_High_Score_Answers'
        ELSE 'No_High_Score_Answers'
    END as HasHighScoreAnswers,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Comments c3 WHERE c3.PostId = ca.Id AND c3.Score > 100) THEN 'Has_High_Score_Comments'
        ELSE 'No_High_Score_Comments'
    END as HasHighScoreComments,
    CASE 
        WHEN ca.Score > 50 AND ca.ViewCount > 1000 THEN 'Viral_Velocity'
        WHEN ca.Score > 25 AND ca.ViewCount > 500 THEN 'Moderate_Velocity'
        WHEN ca.Score > 10 AND ca.ViewCount > 100 THEN 'Slow_Velocity'
        ELSE 'Negligible_Velocity'
    END as VelocityStatus,
    (SELECT AVG(p9.ViewCount) FROM Posts p9 WHERE p9.OwnerUserId = ca.OwnerUserId AND p9.PostTypeId = 1) as OwnerAvgQuestionViews,
    (SELECT AVG(p10.ViewCount) FROM Posts p10 WHERE p10.OwnerUserId = ca.OwnerUserId AND p10.PostTypeId = 2) as OwnerAvgAnswerViews,
    (SELECT STRING_AGG(b2.Name, ', ') FROM Badges b2 WHERE b2.UserId = ca.OwnerUserId) as AllBadges,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = ca.Id AND ph2.UserId = ca.OwnerUserId) as OwnerEditCount,
    CASE 
        WHEN ca.CompositeScore > (SELECT AVG(CompositeScore) FROM CombinedAnalysis) THEN 'Above_Avg_Composite'
        ELSE 'Below_Avg_Composite'
    END as CompositeScoreStatus,
    (SELECT AVG(p11.Score) FROM Posts p11 WHERE p11.PostTypeId = 1 AND p11.CreationDate BETWEEN ca.CreationDate - INTERVAL '7 days' AND ca.CreationDate + INTERVAL '7 days') as WeeklyAverageScore,
    (SELECT AVG(p12.ViewCount) FROM Posts p12 WHERE p12.OwnerUserId = ca.OwnerUserId AND p12.PostTypeId = 1 AND p12.CreationDate >= ca.CreationDate - INTERVAL '30 days') as RecentAvgQuestionViews,
    (SELECT AVG(p13.Score) FROM Posts p13 WHERE p13.OwnerUserId = ca.OwnerUserId AND p13.CreationDate >= ca.CreationDate - INTERVAL '30 days') as RecentAvgScore,
    (ca.Score * 0.6 + ca.ViewCount * 0.2 + ca.AnswerCount * 0.1 + ca.CommentCount * 0.05 + ca.FavoriteCount * 0.05) as WeightedEngagement,
    CASE 
        WHEN ca.PostTypeId = 1 AND ca.AnswerCount > 0 THEN (
            (SELECT COUNT(*) FROM Posts p14 WHERE p14.ParentId = ca.Id AND p14.Score > 50) * 100.0 / NULLIF(ca.AnswerCount, 0)
        ) ELSE NULL
    END as HighScoringAnswerPercentage,
    CASE 
        WHEN ca.OwnerUserId IS NOT NULL AND ca.OwnerUserId > 0 THEN (
            SELECT COUNT(*) FROM Posts p15 WHERE p15.OwnerUserId = ca.OwnerUserId AND p15.PostTypeId = 1
        ) ELSE 0
    END as QuestionCountByOwner
FROM CombinedAnalysis ca
WHERE ca.Score > 0
  AND ca.ViewCount > 0
  AND (ca.OwnerUserId IS NOT NULL OR ca.OwnerUserId > 0)
  AND ca.PostTypeId IN (1, 2)

UNION ALL

SELECT 
    ca.Id,
    ca.PostTypeId,
    ca.Score,
    ca.ViewCount,
    ca.CreationDate,
    ca.OwnerUserId,
    ca.Title,
    ca.Tags,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.ClosedDate,
    ca.rn,
    ca.prev_score,
    ca.moving_avg_score,
    ca.ScoreChange,
    ca.ImpactLevel,
    ca.EngagementCount,
    ca.FavoriteStatus,
    ca.ScoreViewProduct,
    ca.ScoreChangeMagnitude,
    ca.PostYear,
    ca.PostMonth,
    ca.ScoreVsAvgPercent,
    ca.Reputation,
    ca.DisplayName,
    ca.Views,
    ca.UpVotes,
    ca.DownVotes,
    ca.PostCount,
    ca.BadgeCount,
    ca.UserCommentCount,
    ca.LastPostDate,
    ca.ReputationLevel,
    ca.AllTags,
    ca.TagName,
    ca.TagCount,
    ca.ExcerptPostId,
    ca.WikiPostId,
    ca.PopularityLevel,
    ca.popularity_rank,
    ca.count_diff_from_prev,
    ca.PostPopularity,
    ca.PostActivityStatus,
    ca.PotentialCategory,
    ca.ScoreChangePercent,
    ca.ScoreDeviationFromAvg,
    ca.DaysSinceCreation,
    ca.IsOpen,
    ca.TrendingStatus,
    ca.EngagementScore,
    ca.ScoreComparison,
    ca.ChildAnswerCount,
    ca.CommentCountForPost,
    ca.AvgVoteScore,
    ca.FavoriteCountByVotes,
    ca.QuestionAnswerStatus,
    ca.CompositeScore,
    ca.GoldBadgeCount,
    ca.SilverBadgeCount,
    ca.BronzeBadgeCount,
    'CROSS_JOINED_RECORD' as PerformanceCategory,
    ROW_NUMBER() OVER (ORDER BY ca.Score DESC, ca.ViewCount DESC) as OverallRank,
    RANK() OVER (PARTITION BY ca.PostTypeId ORDER BY ca.Score DESC) as TypeRank,
    DENSE_RANK() OVER (ORDER BY ca.Reputation DESC) as ReputationRank,
    NTILE(10) OVER (ORDER BY ca.Score) as ScoreDecile,
    PERCENT_RANK() OVER (ORDER BY ca.ViewCount DESC) as ViewPercentile,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = ca.OwnerUserId AND p3.PostTypeId = 1) as OwnerQuestionCount,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = ca.OwnerUserId AND p4.PostTypeId = 2) as OwnerAnswerCount,
    (SELECT AVG(Score) FROM Posts p5 WHERE p5.OwnerUserId = ca.OwnerUserId AND p5.PostTypeId = 1) as OwnerAvgQuestionScore,
    (SELECT AVG(Score) FROM Posts p6 WHERE p6.OwnerUserId = ca.OwnerUserId AND p6.PostTypeId = 2) as OwnerAvgAnswerScore,
    MAX(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerMaxScore,
    MIN(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerMinScore,
    AVG(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerAvgScore,
    SUM(ca.ViewCount) OVER (PARTITION BY ca.OwnerUserId) as OwnerTotalViews,
    STDDEV(ca.Score) OVER (PARTITION BY ca.OwnerUserId) as OwnerScoreStdDev,
    COUNT(*) OVER (PARTITION BY ca.OwnerUserId) as OwnerPostCount,
    CASE 
        WHEN ca.OwnerAvgQuestionScore > 50 THEN 'Active_Questioner'
        WHEN ca.OwnerAvgAnswerScore > 25 THEN 'Active_Answerer'
        ELSE 'Passive_User'
    END as UserActivityLevel,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.OwnerUserId AND v.VoteTypeId = 2) as OwnerUpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.OwnerUserId AND v.VoteTypeId = 3) as OwnerDownVotes,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = ca.OwnerUserId AND v.VoteTypeId = 8) as OwnerTotalBounty,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ca.OwnerUserId AND c.CreationDate >= ca.CreationDate - INTERVAL '30 days') as RecentComments,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.OwnerUserId AND b.Date >= ca.CreationDate - INTERVAL '30 days') as RecentBadges,
    CASE 
        WHEN ca.PostTypeId = 1 AND ca.Score > 100 AND ca.AnswerCount > 5 THEN 'Highly_Questioned'
        WHEN ca.PostTypeId = 2 AND ca.Score > 50 THEN 'Highly_Valued_Answer'
        ELSE 'Ordinary_Post'
    END as PostClassification,
    NULLIF(ca.Score, 0) as SafeScore,
    COALESCE(ca.Tags, '') as SafeTags,
    (ca.Score + ca.ViewCount + ca.AnswerCount + ca.CommentCount + ca.FavoriteCount) as TotalActivityIndicator,
    CASE 
        WHEN ca.ScoreChange = 'Increased' AND ca.Score > 0 THEN 'Growing_Importance'
        WHEN ca.ScoreChange = 'Decreased' AND ca.Score < 0 THEN 'Declining_Importance'
        ELSE 'Stable_Importance'
    END as ImportanceTrend,
    CASE 
        WHEN ca.ImpactLevel = 'High Impact' AND ca.FavoriteStatus = 'Favored' THEN 'Highly_Boosted'
        WHEN ca.ImpactLevel = 'Medium Impact' AND ca.FavoriteStatus = 'Favored' THEN 'Moderately_Boosted'
        ELSE 'Regular'
    END as BoostingStatus,
    (SELECT COUNT(*) FROM Posts p7 WHERE p7.ParentId = ca.Id AND p7.CreationDate >= ca.CreationDate + INTERVAL '1 day') as ImmediateAnswers,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = ca.Id AND ph.PostHistoryTypeId IN (2, 5, 10, 11, 12, 13, 16, 17, 18, 19, 20, 22, 24) AND ph.CreationDate >= ca.CreationDate) as EditCount,
    LAG(ca.Score) OVER (ORDER BY ca.CreationDate) as PrevScore,
    LEAD(ca.Score) OVER (ORDER BY ca.CreationDate) as NextScore,
    FIRST_VALUE(ca.Score) OVER (ORDER BY ca.CreationDate) as FirstScore,
    LAST_VALUE(ca.Score) OVER (ORDER BY ca.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as LastScore,
    NTH_VALUE(ca.Score, 3) OVER (ORDER BY ca.CreationDate) as ThirdScore,
    ROW_NUMBER() OVER (ORDER BY ca.ViewCount DESC) - ROW_NUMBER() OVER (ORDER BY ca.Score DESC) as ViewScoreRankGap,
    LAG(ca.ViewCount) OVER (ORDER BY ca.CreationDate) - ca.ViewCount as ViewChange,
    LEAD(ca.ViewCount) OVER (ORDER BY ca.CreationDate) - ca.ViewCount as NextViewChange,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p8 WHERE p8.ParentId = ca.Id AND p8.Score > 100) THEN 'Has_High_Score_Answers'
        ELSE 'No_High_Score_Answers'
    END as HasHighScoreAnswers,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Comments c3 WHERE c3.PostId = ca.Id AND c3.Score > 100) THEN 'Has_High_Score_Comments'
        ELSE 'No_High_Score_Comments'
    END as HasHighScoreComments,
    CASE 
        WHEN ca.Score > 50 AND ca.ViewCount > 1000 THEN 'Viral_Velocity'
        WHEN ca.Score > 25 AND ca.ViewCount > 500 THEN 'Moderate_Velocity'
        WHEN ca.Score > 10 AND ca.ViewCount > 100 THEN 'Slow_Velocity'
        ELSE 'Negligible_Velocity'
    END as VelocityStatus,
    (SELECT AVG(p9.ViewCount) FROM Posts p9 WHERE p9.OwnerUserId = ca.OwnerUserId AND p9.PostTypeId = 1) as OwnerAvgQuestionViews,
    (SELECT AVG(p10.ViewCount) FROM Posts p10 WHERE p10.OwnerUserId = ca.OwnerUserId AND p10.PostTypeId = 2) as OwnerAvgAnswerViews,
    (SELECT STRING_AGG(b2.Name, ', ') FROM Badges b2 WHERE b2.UserId = ca.OwnerUserId) as AllBadges,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = ca.Id AND ph2.UserId = ca.OwnerUserId) as OwnerEditCount,
    CASE 
        WHEN ca.CompositeScore > (SELECT AVG(CompositeScore) FROM CombinedAnalysis) THEN 'Above_Avg_Composite'
        ELSE 'Below_Avg_Composite'
    END as CompositeScoreStatus,
    (SELECT AVG(p11.Score) FROM Posts p11 WHERE p11.PostTypeId = 1 AND p11.CreationDate BETWEEN ca.CreationDate - INTERVAL '7 days' AND ca.CreationDate + INTERVAL '7 days') as WeeklyAverageScore,
    (SELECT AVG(p12.ViewCount) FROM Posts p12 WHERE p12.OwnerUserId = ca.OwnerUserId AND p12.PostTypeId = 1 AND p12.CreationDate >= ca.CreationDate - INTERVAL '30 days') as RecentAvgQuestionViews,
    (SELECT AVG(p13.Score) FROM Posts p13 WHERE p13.OwnerUserId = ca.OwnerUserId AND p13.CreationDate >= ca.CreationDate - INTERVAL '30 days') as RecentAvgScore,
    (ca.Score * 0.6 + ca.ViewCount * 0.2 + ca.AnswerCount * 0.1 + ca.CommentCount * 0.05 + ca.FavoriteCount * 0.05) as WeightedEngagement,
    CASE 
        WHEN ca.PostTypeId = 1 AND ca.AnswerCount > 0 THEN (
            (SELECT COUNT(*) FROM Posts p14 WHERE p14.ParentId = ca.Id AND p14.Score > 50) * 100.0 / NULLIF(ca.AnswerCount, 0)
        ) ELSE NULL
    END as HighScoringAnswerPercentage,
    CASE 
        WHEN ca.OwnerUserId IS NOT NULL AND ca.OwnerUserId > 0 THEN (
            SELECT COUNT(*) FROM Posts p15 WHERE p15.OwnerUserId = ca.OwnerUserId AND p15.PostTypeId = 1
        ) ELSE 0
    END as QuestionCountByOwner
FROM CombinedAnalysis ca
WHERE ca.Score > 0
  AND ca.ViewCount > 0
  AND (ca.OwnerUserId IS NOT NULL OR ca.OwnerUserId > 0)
  AND ca.PostTypeId IN (1, 2)
  AND EXISTS (
    SELECT 1 FROM Posts p16 
    WHERE p16.ParentId = ca.Id 
      AND p16.Score > 100 
      AND p16.CreationDate >= ca.CreationDate - INTERVAL '30 days'
  )
  AND EXISTS (
    SELECT 1 FROM Comments c4 
    WHERE c4.PostId = ca.Id 
      AND c4.Score > 50 
      AND c4.CreationDate >= ca.CreationDate - INTERVAL '30 days'
  )
  AND EXISTS (
    SELECT 1 FROM Badges b3 
    WHERE b3.UserId = ca.OwnerUserId 
      AND b3.Date >= ca.CreationDate - INTERVAL '7 days'
  )
  AND ca.Reputation > 5000
  AND ca.PostCount BETWEEN 10 AND 100
  AND ca.LastPostDate >= '2020-01-01'
ORDER BY ca.Score DESC, ca.ViewCount DESC, ca.CreationDate DESC