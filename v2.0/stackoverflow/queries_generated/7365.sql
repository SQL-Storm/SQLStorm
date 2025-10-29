-- {"query": "7365.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3177} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END AS ReputationTier,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (ORDER BY u.Views DESC) AS ViewRank,
        NTILE(10) OVER (ORDER BY u.Reputation) AS ReputationQuartile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' 
      AND u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
    HAVING COUNT(DISTINCT p.Id) > 0
),
PostPerformanceMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END AS VoteCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            WHEN p.ViewCount > 0 THEN 'Low'
            ELSE 'Unseen'
        END AS Popularity,
        DATEDIFF(CURDATE(), p.CreationDate) AS AgeDays,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LAG(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousViews,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        STDDEV(p.Score) OVER (PARTITION BY p.OwnerUserId) AS StdDevScore,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRank,
        RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank
    FROM Posts p
    WHERE p.CreationDate >= '2019-01-01' 
      AND p.PostTypeId IN (1, 2)
),
UserPostActivity AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.ReputationTier,
        uas.ReputationRank,
        uas.ViewRank,
        SUM(ppm.Score) AS TotalPostScore,
        AVG(ppm.Score) AS AvgPostScore,
        AVG(ppm.ViewCount) AS AvgViews,
        MAX(ppm.Score) AS MaxPostScore,
        COUNT(ppm.PostId) AS PostCount,
        STRING_AGG(ppm.Title, '; ') WITHIN GROUP (ORDER BY ppm.Score DESC) AS TopTitles,
        COUNT(DISTINCT ppm.PostType) AS PostTypesUsed,
        AVG(ppm.AgeDays) AS AvgAge,
        STDDEV(ppm.AgeDays) AS StdDevAge,
        CASE 
            WHEN SUM(CASE WHEN ppm.Score > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(ppm.PostId) > 0.8 THEN 'HighlyVoted'
            WHEN SUM(CASE WHEN ppm.Score > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(ppm.PostId) > 0.5 THEN 'ModerateVoted'
            ELSE 'LowVoted'
        END AS VotingPattern,
        CASE 
            WHEN AVG(ppm.ViewCount) > 500 THEN 'Active'
            WHEN AVG(ppm.ViewCount) > 100 THEN 'Moderate'
            ELSE 'Quiet'
        END AS ActivityLevel
    FROM UserActivityStats uas
    JOIN PostPerformanceMetrics ppm ON uas.UserId = ppm.OwnerUserId
    WHERE ppm.Score IS NOT NULL
    GROUP BY uas.UserId, uas.DisplayName, uas.ReputationTier, uas.ReputationRank, uas.ViewRank
),
ComplexAnalytics AS (
    SELECT 
       upa.UserId,
        upa.DisplayName,
        upa.ReputationTier,
        upa.ReputationRank,
        upa.ViewRank,
        upa.TotalPostScore,
        upa.AvgPostScore,
        upa.AvgViews,
        upa.MaxPostScore,
        upa.PostCount,
        upa.TopTitles,
        upa.PostTypesUsed,
        upa.AvgAge,
        upa.StdDevAge,
        upa.VotingPattern,
        upa.ActivityLevel,
        CASE 
            WHEN upa.ReputationRank <= 100 AND upa.ViewRank <= 100 THEN 'EliteContributor'
            WHEN upa.ReputationRank <= 500 AND upa.ViewRank <= 500 THEN 'TopContributor'
            WHEN upa.ReputationRank <= 1000 AND upa.ViewRank <= 1000 THEN 'ActiveContributor'
            ELSE 'RegularContributor'
        END AS ContributionTier,
        (upa.TotalPostScore * 1.0 / NULLIF(upa.PostCount, 0)) AS AvgScorePerPost,
        (upa.AvgViews * 1.0 / NULLIF(upa.PostCount, 0)) AS AvgViewsPerPost,
        CASE 
            WHEN upa.StdDevAge IS NOT NULL AND upa.StdDevAge > 180 THEN 'DiverseAge'
            WHEN upa.StdDevAge IS NOT NULL AND upa.StdDevAge > 90 THEN 'ModerateAge'
            ELSE 'ConsistentAge'
        END AS AgeConsistency,
        CASE 
            WHEN upa.PostCount >= 100 AND upa.AvgScorePerPost >= 20 THEN 'HighPerforming'
            WHEN upa.PostCount >= 50 AND upa.AvgScorePerPost >= 10 THEN 'MediumPerforming'
            WHEN upa.PostCount >= 10 AND upa.AvgScorePerPost >= 5 THEN 'LowPerforming'
            ELSE 'Underperforming'
        END AS PerformanceCategory,
        DENSE_RANK() OVER (ORDER BY upa.TotalPostScore DESC) AS ScoreRankOverall,
        DENSE_RANK() OVER (ORDER BY upa.AvgViews DESC) AS ViewsRankOverall,
        ROW_NUMBER() OVER (ORDER BY upa.ReputationRank ASC, upa.ViewRank ASC) AS CombinedRank
    FROM UserPostActivity upa
),
StatisticalComparisons AS (
    SELECT 
        ca.UserId,
        ca.DisplayName,
        ca.ReputationTier,
        ca.ReputationRank,
        ca.ViewRank,
        ca.TotalPostScore,
        ca.AvgPostScore,
        ca.AvgViews,
        ca.MaxPostScore,
        ca.PostCount,
        ca.TopTitles,
        ca.PostTypesUsed,
        ca.AvgAge,
        ca.StdDevAge,
        ca.VotingPattern,
        ca.ActivityLevel,
        ca.ContributionTier,
        ca.AvgScorePerPost,
        ca.AvgViewsPerPost,
        ca.AgeConsistency,
        ca.PerformanceCategory,
        ca.ScoreRankOverall,
        ca.ViewsRankOverall,
        ca.CombinedRank,
        (SELECT AVG(AvgPostScore) FROM StatisticalComparisons) AS OverallAvgScore,
        (SELECT AVG(AvgViews) FROM StatisticalComparisons) AS OverallAvgViews,
        (SELECT MAX(MaxPostScore) FROM StatisticalComparisons) AS MaxScoreOverall,
        PERCENT_RANK() OVER (ORDER BY ca.AvgPostScore) AS ScorePercentile,
        PERCENT_RANK() OVER (ORDER BY ca.AvgViews) AS ViewsPercentile,
        CUME_DIST() OVER (ORDER BY ca.AvgPostScore) AS ScoreDistribution,
        CUME_DIST() OVER (ORDER BY ca.AvgViews) AS ViewsDistribution,
        NTILE(4) OVER (ORDER BY ca.AvgPostScore) AS ScoreQuartile,
        NTILE(4) OVER (ORDER BY ca.AvgViews) AS ViewsQuartile,
        CASE 
            WHEN ca.AvgPostScore > (SELECT AVG(AvgPostScore) FROM StatisticalComparisons) THEN 'AboveAverage'
            WHEN ca.AvgPostScore > (SELECT AVG(AvgPostScore) FROM StatisticalComparisons) * 0.8 THEN 'Average'
            ELSE 'BelowAverage'
        END AS ScoreLevel,
        CASE 
            WHEN ca.AvgViews > (SELECT AVG(AvgViews) FROM StatisticalComparisons) THEN 'AboveAverageViews'
            WHEN ca.AvgViews > (SELECT AVG(AvgViews) FROM StatisticalComparisons) * 0.8 THEN 'AverageViews'
            ELSE 'BelowAverageViews'
        END AS ViewsLevel
    FROM ComplexAnalytics ca
)
SELECT 
    sc.UserId,
    sc.DisplayName,
    sc.ReputationTier,
    sc.ReputationRank,
    sc.ViewRank,
    sc.TotalPostScore,
    sc.AvgPostScore,
    sc.AvgViews,
    sc.MaxPostScore,
    sc.PostCount,
    sc.TopTitles,
    sc.PostTypesUsed,
    sc.AvgAge,
    sc.StdDevAge,
    sc.VotingPattern,
    sc.ActivityLevel,
    sc.ContributionTier,
    sc.AvgScorePerPost,
    sc.AvgViewsPerPost,
    sc.AgeConsistency,
    sc.PerformanceCategory,
    sc.ScoreRankOverall,
    sc.ViewsRankOverall,
    sc.CombinedRank,
    sc.OverallAvgScore,
    sc.OverallAvgViews,
    sc.MaxScoreOverall,
    sc.ScorePercentile,
    sc.ViewsPercentile,
    sc.ScoreDistribution,
    sc.ViewsDistribution,
    sc.ScoreQuartile,
    sc.ViewsQuartile,
    sc.ScoreLevel,
    sc.ViewsLevel,
    CASE 
        WHEN sc.ScoreLevel = 'AboveAverage' AND sc.ViewsLevel = 'AboveAverageViews' AND sc.PerformanceCategory = 'HighPerforming' THEN 'SuperStar'
        WHEN sc.ScoreLevel = 'AboveAverage' OR sc.ViewsLevel = 'AboveAverageViews' THEN 'Notable'
        ELSE 'Standard'
    END AS RecognitionCategory,
    LAG(sc.ScoreRankOverall, 1) OVER (ORDER BY sc.CombinedRank) AS PrevScoreRank,
    LEAD(sc.ScoreRankOverall, 1) OVER (ORDER BY sc.CombinedRank) AS NextScoreRank,
    AVG(sc.AvgPostScore) OVER (ORDER BY sc.CombinedRank ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS MovingAvgScore,
    SUM(sc.TotalPostScore) OVER (ORDER BY sc.CombinedRank) AS CumulativeScore,
    COUNT(*) OVER () AS TotalUsers,
    CASE 
        WHEN sc.CombinedRank <= 10 THEN 'Top10'
        WHEN sc.CombinedRank <= 50 THEN 'Top50'
        WHEN sc.CombinedRank <= 100 THEN 'Top100'
        ELSE 'BeyondTop100'
    END AS RankingTier,
    (CASE WHEN sc.ContributionTier = 'EliteContributor' THEN 1 ELSE 0 END +
     CASE WHEN sc.PerformanceCategory = 'HighPerforming' THEN 1 ELSE 0 END +
     CASE WHEN sc.ScoreLevel = 'AboveAverage' THEN 1 ELSE 0 END +
     CASE WHEN sc.ViewsLevel = 'AboveAverageViews' THEN 1 ELSE 0 END +
     CASE WHEN sc.AgeConsistency = 'DiverseAge' THEN 1 ELSE 0 END) AS AchievementCount,
    ROW_NUMBER() OVER (ORDER BY (CASE WHEN sc.ContributionTier = 'EliteContributor' THEN 1 ELSE 0 END +
                              CASE WHEN sc.PerformanceCategory = 'HighPerforming' THEN 1 ELSE 0 END +
                              CASE WHEN sc.ScoreLevel = 'AboveAverage' THEN 1 ELSE 0 END +
                              CASE WHEN sc.ViewsLevel = 'AboveAverageViews' THEN 1 ELSE 0 END +
                              CASE WHEN sc.AgeConsistency = 'DiverseAge' THEN 1 ELSE 0 END) DESC) AS CompositeRank,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = sc.UserId AND b.Class = 1) THEN 'GoldBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = sc.UserId AND b.Class = 2) THEN 'SilverBadgeHolder'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = sc.UserId AND b.Class = 3) THEN 'BronzeBadgeHolder'
        ELSE 'NoBadge'
    END AS BadgeStatus,
    CASE 
        WHEN sc.PostCount > (SELECT AVG(PostCount) FROM StatisticalComparisons) THEN 'AboveAveragePostCount'
        WHEN sc.PostCount > (SELECT AVG(PostCount) FROM StatisticalComparisons) * 0.8 THEN 'AveragePostCount'
        ELSE 'BelowAveragePostCount'
    END AS PostCountStatus,
    sc.ViewRank,
    (SELECT COUNT(*) FROM Users WHERE AccountId = (SELECT AccountId FROM Users WHERE Id = sc.UserId)) AS AccountMemberships,
    CONCAT('User-', sc.UserId, '-Rank-', sc.CombinedRank) AS UserIdentifier,
    CONCAT(sc.DisplayName, ' (', CASE WHEN sc.ReputationTier = 'Elite' THEN '★' WHEN sc.ReputationTier = 'Veteran' THEN '♦' WHEN sc.ReputationTier = 'Regular' THEN '♣' ELSE '♠' END, ')') AS FormattedDisplayName
FROM StatisticalComparisons sc
WHERE sc.PostCount > 0 
  AND sc.AvgPostScore >= 0
  AND (sc.ScoreLevel = 'AboveAverage' OR sc.ViewsLevel = 'AboveAverageViews')
ORDER BY sc.CombinedRank ASC, sc.AvgPostScore DESC
LIMIT 500;