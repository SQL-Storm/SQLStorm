-- {"query": "7341.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2283} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LatestPostDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                DATEDIFF('day', MIN(p.CreationDate), MAX(p.CreationDate))
            ELSE 0 
        END as ActiveDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Gold'
            WHEN u.Reputation > 1000 THEN 'Silver'
            ELSE 'Bronze'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
RankedPosts AS (
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
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as GlobalRank,
        LAG(p.Score, 1) OVER (ORDER BY p.Score DESC) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.Score DESC) as NextScore,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTILE(4) OVER (ORDER BY p.Score) as Quartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostAnalysis AS (
    SELECT 
        r.PostId,
        r.Title,
        r.Score,
        r.ViewCount,
        r.CreationDate,
        r.OwnerUserId,
        r.PostTypeId,
        r.Tags,
        r.AnswerCount,
        r.CommentCount,
        r.FavoriteCount,
        r.RankByScore,
        r.RankByDate,
        r.GlobalRank,
        r.PrevScore,
        r.NextScore,
        r.ScorePercentile,
        r.Quartile,
        CASE 
            WHEN r.Score = 0 THEN 'Zero'
            WHEN r.Score < 0 THEN 'Negative'
            WHEN r.Score BETWEEN 1 AND 10 THEN 'Low'
            WHEN r.Score BETWEEN 11 AND 50 THEN 'Medium'
            WHEN r.Score BETWEEN 51 AND 100 THEN 'High'
            ELSE 'Extreme'
        END as ScoreCategory,
        CASE 
            WHEN r.AnswerCount IS NULL THEN 'No Answers'
            WHEN r.AnswerCount = 0 THEN 'No Answers'
            WHEN r.AnswerCount BETWEEN 1 AND 3 THEN 'Few Answers'
            WHEN r.AnswerCount BETWEEN 4 AND 10 THEN 'Moderate Answers'
            ELSE 'Many Answers'
        END as AnswerCategory,
        CASE 
            WHEN r.CommentCount > 10 THEN 'Highly Commented'
            WHEN r.CommentCount > 5 THEN 'Moderately Commented'
            WHEN r.CommentCount > 0 THEN 'Slightly Commented'
            ELSE 'Not Commented'
        END as CommentCategory,
        COALESCE(
            SPLIT_PART(r.Tags, '>', 1),
            SPLIT_PART(r.Tags, '>', 2),
            SPLIT_PART(r.Tags, '>', 3)
        ) as FirstTag,
        LENGTH(r.Title) as TitleLength,
        EXTRACT(YEAR FROM r.CreationDate) as YearCreated,
        CASE 
            WHEN r.CreationDate > NOW() - INTERVAL '30 days' THEN 'Recent'
            WHEN r.CreationDate > NOW() - INTERVAL '90 days' THEN 'Medium'
            ELSE 'Old'
        END as TimeCategory
    FROM RankedPosts r
),
PostMetrics AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostTypeId,
        pa.Tags,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.RankByScore,
        pa.RankByDate,
        pa.GlobalRank,
        pa.PrevScore,
        pa.NextScore,
        pa.ScorePercentile,
        pa.Quartile,
        pa.ScoreCategory,
        pa.AnswerCategory,
        pa.CommentCategory,
        pa.FirstTag,
        pa.TitleLength,
        pa.YearCreated,
        pa.TimeCategory,
        COALESCE(pa.Score, 0) + COALESCE(pa.ViewCount, 0) + COALESCE(pa.CommentCount, 0) as CompositeMetric,
        CASE 
            WHEN pa.ScorePercentile > 0.95 THEN 'Top 5%'
            WHEN pa.ScorePercentile > 0.75 THEN 'Top 25%'
            WHEN pa.ScorePercentile > 0.5 THEN 'Top 50%'
            ELSE 'Below Average'
        END as PerformanceQuartile,
        CASE 
            WHEN pa.AnswerCount > 0 AND pa.Score > 0 THEN 
                CAST(pa.AnswerCount AS FLOAT) / CAST(pa.Score AS FLOAT)
            ELSE 0 
        END as AnswerToScoreRatio,
        DENSE_RANK() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as UserScoreRank
    FROM PostAnalysis pa
),
TaggedPosts AS (
    SELECT 
        pm.PostId,
        pm.Title,
        pm.Score,
        pm.ViewCount,
        pm.CreationDate,
        pm.OwnerUserId,
        pm.FirstTag,
        pm.ScoreCategory,
        pm.AnswerCategory,
        pm.CommentCategory,
        pm.TimeCategory,
        pm.CompositeMetric,
        pm.PerformanceQuartile,
        pm.AnswerToScoreRatio,
        pm.UserScoreRank,
        CASE 
            WHEN pm.FirstTag IS NOT NULL AND pm.FirstTag != '' THEN 
                COALESCE(pm.FirstTag, 'Unknown')
            ELSE 'No Tag'
        END as TagGrouping,
        ROW_NUMBER() OVER (PARTITION BY pm.FirstTag ORDER BY pm.Score DESC) as TagRanking
    FROM PostMetrics pm
    WHERE pm.FirstTag IS NOT NULL AND pm.FirstTag != ''
),
UserPostAggregates AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.ReputationTier,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.AvgPostScore,
        us.ActiveDays,
        SUM(tpa.CompositeMetric) as TotalCompositeScore,
        AVG(tpa.CompositeMetric) as AvgCompositeScore,
        MAX(tpa.CompositeMetric) as MaxCompositeScore,
        COUNT(tpa.PostId) as TaggedPostCount,
        COUNT(CASE WHEN tpa.TagGrouping != 'No Tag' THEN 1 END) as TaggedPosts,
        COUNT(CASE WHEN tpa.ScoreCategory = 'Extreme' THEN 1 END) as ExtremeScorePosts,
        COUNT(CASE WHEN tpa.CommentCategory = 'Highly Commented' THEN 1 END) as HighlyCommentedPosts,
        COUNT(CASE WHEN tpa.TimeCategory = 'Recent' THEN 1 END) as RecentPosts
    FROM UserStats us
    LEFT JOIN TaggedPosts tpa ON us.UserId = tpa.OwnerUserId
    WHERE us.PostCount > 0
    GROUP BY us.UserId, us.DisplayName, us.Reputation, us.ReputationTier, us.PostCount, us.CommentCount, us.BadgeCount, us.AvgPostScore, us.ActiveDays
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.ReputationTier,
    upa.PostCount,
    upa.CommentCount,
    upa.BadgeCount,
    upa.AvgPostScore,
    upa.ActiveDays,
    upa.TotalCompositeScore,
    upa.AvgCompositeScore,
    upa.MaxCompositeScore,
    upa.TaggedPostCount,
    upa.TaggedPosts,
    upa.ExtremeScorePosts,
    upa.HighlyCommentedPosts,
    upa.RecentPosts,
    CASE 
        WHEN upa.Reputation > 10000 AND upa.TaggedPosts > 10 THEN 'Elite Contributor'
        WHEN upa.Reputation > 5000 AND upa.TaggedPosts > 5 THEN 'Active Contributor'
        WHEN upa.Reputation > 1000 AND upa.TaggedPosts > 1 THEN 'Regular Contributor'
        ELSE 'New Contributor'
    END as ContributorStatus,
    ROW_NUMBER() OVER (ORDER BY upa.TotalCompositeScore DESC) as OverallRank,
    DENSE_RANK() OVER (ORDER BY upa.Reputation DESC) as ReputationRank,
    PERCENT_RANK() OVER (ORDER BY upa.TotalCompositeScore) as ScorePercentile,
    NTILE(5) OVER (ORDER BY upa.TotalCompositeScore) as Quintile,
    AVG(upa.TotalCompositeScore) OVER (PARTITION BY upa.ReputationTier) as TierAverageScore,
    COUNT(*) OVER () as TotalContributors,
    (upa.TotalCompositeScore - AVG(upa.TotalCompositeScore) OVER ()) / 
    (STDDEV(upa.TotalCompositeScore) OVER () + 0.001) as ZScore,
    STDEV(upa.TotalCompositeScore) OVER (PARTITION BY upa.ReputationTier) as TierStandardDeviation
FROM UserPostAggregates upa
INNER JOIN (
    SELECT 
        UserId,
        COUNT(DISTINCT PostId) as PostCount,
        SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) as PositiveScores,
        SUM(CASE WHEN Score < 0 THEN 1 ELSE 0 END) as NegativeScores
    FROM Posts
    WHERE PostTypeId IN (1, 2)
    GROUP BY UserId
    HAVING COUNT(DISTINCT PostId) > 0
) p ON upa.UserId = p.UserId
WHERE upa.Reputation > 0
HAVING COUNT(*) > 1
ORDER BY upa.TotalCompositeScore DESC, upa.Reputation DESC
LIMIT 100;