-- {"query": "7845.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2331} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT COALESCE(p.AcceptedAnswerId, 0)) AS AcceptedAnswers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) AS ViewRank,
        NTILE(10) OVER (ORDER BY u.DownVotes) AS DownVoteDecile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
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
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) AS AgeInDays,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'LowVoted'
            ELSE 'Unvoted'
        END AS VotingCategory,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'ModeratelyPopular'
            ELSE 'LittleKnown'
        END AS PopularityLevel
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ComplexUserAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.ReputationRank,
        uas.ViewRank,
        uas.DownVoteDecile,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.AcceptedAnswers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        CASE 
            WHEN uas.TotalPosts > 100 AND uas.Reputation > 5000 THEN 'EliteContributor'
            WHEN uas.TotalPosts > 50 THEN 'ActiveContributor'
            WHEN uas.TotalPosts > 10 THEN 'RegularContributor'
            ELSE 'OccasionalContributor'
        END AS ContributionTier,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY uas.TotalPosts) OVER() AS MedianPosts,
        AVG(uas.Views) OVER (PARTITION BY uas.DownVoteDecile) AS AvgViewsByDownVoteDecile,
        LAG(uas.Reputation, 1) OVER (ORDER BY uas.Reputation DESC) - uas.Reputation AS RepDifferenceFromAbove,
        LEAD(uas.Reputation, 1) OVER (ORDER BY uas.Reputation DESC) - uas.Reputation AS RepDifferenceFromBelow
    FROM UserActivityStats uas
),
UserPostRelationships AS (
    SELECT 
        cua.UserId,
        cua.DisplayName,
        cua.Reputation,
        cua.TotalPosts,
        cua.ContributionTier,
        cua.ReputationRank,
        cua.ViewRank,
        ppm.PostId,
        ppm.Title,
        ppm.Score,
        ppm.ViewCount,
        ppm.AnswerCount,
        ppm.CommentCount,
        ppm.FavoriteCount,
        ppm.AgeInDays,
        ppm.VotingCategory,
        ppm.PopularityLevel,
        CASE 
            WHEN cua.Reputation > 5000 AND ppm.Score > 100 THEN 'HighValueInteraction'
            WHEN ppm.Score > 50 AND ppm.ViewCount > 1000 THEN 'EngagementHigh'
            WHEN ppm.Score > 10 OR ppm.ViewCount > 100 THEN 'EngagementModerate'
            ELSE 'EngagementLow'
        END AS EngagementLevel,
        RANK() OVER (PARTITION BY cua.UserId ORDER BY ppm.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY ppm.Score DESC) AS GlobalScoreRank,
        DATEDIFF('day', cua.LastPostDate, ppm.CreationDate) AS DaysSinceLastPost
    FROM ComplexUserAnalysis cua
    LEFT JOIN PostPerformanceMetrics ppm ON cua.UserId = ppm.OwnerUserId
),
FinalAggregatedData AS (
    SELECT 
        upr.UserId,
        upr.DisplayName,
        upr.Reputation,
        upr.TotalPosts,
        upr.ContributionTier,
        upr.ReputationRank,
        upr.ViewRank,
        upr.PostId,
        upr.Title,
        upr.Score,
        upr.ViewCount,
        upr.AnswerCount,
        upr.CommentCount,
        upr.FavoriteCount,
        upr.AgeInDays,
        upr.VotingCategory,
        upr.PopularityLevel,
        upr.EngagementLevel,
        upr.ScoreRank,
        upr.GlobalScoreRank,
        upr.DaysSinceLastPost,
        CASE 
            WHEN upr.AgeInDays < 30 AND upr.Score > 50 THEN 'FreshHighVoted'
            WHEN upr.AgeInDays > 365 AND upr.Score > 100 THEN 'VeteranHighVoted'
            WHEN upr.AgeInDays BETWEEN 30 AND 365 AND upr.Score > 50 THEN 'EstablishedModerateVoted'
            ELSE 'Other'
        END AS TemporalVotingPattern,
        CASE 
            WHEN (upr.Score + COALESCE(upr.ViewCount, 0) + COALESCE(upr.AnswerCount, 0) + COALESCE(upr.CommentCount, 0) + COALESCE(upr.FavoriteCount, 0)) > 500 THEN 'HighImpact'
            WHEN (upr.Score + COALESCE(upr.ViewCount, 0) + COALESCE(upr.AnswerCount, 0) + COALESCE(upr.CommentCount, 0) + COALESCE(upr.FavoriteCount, 0)) > 100 THEN 'MediumImpact'
            ELSE 'LowImpact'
        END AS ImpactLevel,
        LAG(upr.Score, 1) OVER (ORDER BY upr.UserId, upr.CreationDate) AS PrevScore,
        COALESCE(upr.Score, 0) - COALESCE(LAG(upr.Score, 1) OVER (ORDER BY upr.UserId, upr.CreationDate), 0) AS ScoreChange,
        ROW_NUMBER() OVER (PARTITION BY upr.UserId ORDER BY upr.CreationDate DESC) AS RecencyRank,
        COUNT(*) OVER (PARTITION BY upr.UserId) AS UserPostCount
    FROM UserPostRelationships upr
    WHERE upr.PostId IS NOT NULL
)
SELECT 
    fad.UserId,
    fad.DisplayName,
    fad.Reputation,
    fad.TotalPosts,
    fad.ContributionTier,
    fad.PostId,
    fad.Title,
    fad.Score,
    fad.ViewCount,
    fad.AnswerCount,
    fad.CommentCount,
    fad.FavoriteCount,
    fad.AgeInDays,
    fad.VotingCategory,
    fad.PopularityLevel,
    fad.EngagementLevel,
    fad.TemporalVotingPattern,
    fad.ImpactLevel,
    fad.ScoreChange,
    CASE 
        WHEN fad.ScoreChange > 0 THEN 'Positive'
        WHEN fad.ScoreChange < 0 THEN 'Negative'
        ELSE 'NoChange'
    END AS ScoreTrend,
    fad.ReputationRank,
    fad.ViewRank,
    fad.RecencyRank,
    fad.UserPostCount,
    RANK() OVER (ORDER BY fad.Score DESC) AS GlobalRank,
    DENSE_RANK() OVER (ORDER BY fad.ImpactLevel, fad.Score DESC) AS ImpactScoreRank,
    STRING_AGG(fad.Title, '; ') WITHIN GROUP (ORDER BY fad.CreationDate) AS UserPostTitles,
    MAX(fad.ViewCount) OVER (PARTITION BY fad.UserId) AS MaxUserViews,
    AVG(fad.Score) OVER (PARTITION BY fad.UserId) AS AvgUserScore,
    COALESCE(fad.Score, 0) + COALESCE(fad.ViewCount, 0) + COALESCE(fad.AnswerCount, 0) AS ScoreMetric,
    COALESCE(fad.ViewCount, 0) * 0.1 + COALESCE(fad.AnswerCount, 0) * 2.0 + COALESCE(fad.Score, 0) * 5.0 AS WeightedScoreMetric,
    CASE 
        WHEN fad.ViewCount IS NULL THEN 'MissingViews'
        WHEN fad.ViewCount = 0 THEN 'NoViews'
        WHEN fad.ViewCount BETWEEN 1 AND 10 THEN 'LowViews'
        WHEN fad.ViewCount BETWEEN 11 AND 100 THEN 'ModerateViews'
        WHEN fad.ViewCount BETWEEN 101 AND 1000 THEN 'HighViews'
        WHEN fad.ViewCount > 1000 THEN 'VeryHighViews'
        ELSE 'Unknown'
    END AS ViewCategory
FROM FinalAggregatedData fad
WHERE fad.Reputation > 1000
    AND (fad.ContributionTier IN ('EliteContributor', 'ActiveContributor')
         OR fad.EngagementLevel IN ('HighValueInteraction', 'EngagementHigh'))
    AND (fad.AgeInDays BETWEEN 0 AND 3650)
    AND fad.TemporalVotingPattern IN ('FreshHighVoted', 'VeteranHighVoted', 'EstablishedModerateVoted')
    AND fad.ImpactLevel IN ('HighImpact', 'MediumImpact')
    AND fad.Score > 10
    AND COALESCE(fad.ViewCount, 0) >= 0
    AND (fad.ScoreChange IS NULL OR ABS(fad.ScoreChange) >= 1)
ORDER BY fad.Score DESC, fad.ViewCount DESC, fad.CreationDate DESC
LIMIT 100;