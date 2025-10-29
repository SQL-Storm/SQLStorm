-- {"query": "7588.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1746} 
WITH UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ' | ') AS TagList,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF('DAY', u.CreationDate, CURRENT_TIMESTAMP) AS AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Active'
            ELSE 'Newbie'
        END AS ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.CreationDate
),
TopPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        RANK() OVER (ORDER BY p.Score DESC) AS OverallScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score DESC) AS ScorePercentile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
PostAnalysis AS (
    SELECT 
        tp.PostId,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.OwnerUserId,
        tp.PostTypeId,
        tp.Tags,
        tp.ScoreRank,
        tp.OverallScoreRank,
        tp.ScorePercentile,
        CASE 
            WHEN tp.Score > 100 THEN 'Viral'
            WHEN tp.Score > 50 THEN 'Popular'
            WHEN tp.Score > 10 THEN 'Noticeable'
            ELSE 'Ordinary'
        END AS ScoreCategory,
        COALESCE(ue.DisplayName, 'Unknown') AS OwnerDisplayName,
        COALESCE(ue.Reputation, 0) AS OwnerReputation,
        COALESCE(ue.ReputationTier, 'Unknown') AS OwnerTier,
        CASE 
            WHEN tp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = tp.PostTypeId) THEN 1
            ELSE 0
        END AS AboveAverage,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = tp.PostId), 0) AS CommentCount,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.PostId AND v.VoteTypeId = 2), 0) AS UpvoteCount,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.PostId AND v.VoteTypeId = 3), 0) AS DownvoteCount
    FROM TopPosts tp
    LEFT JOIN UserEngagement ue ON tp.OwnerUserId = ue.UserId
    WHERE tp.ScoreRank <= 100
),
ComplexCalculations AS (
    SELECT 
        pa.*,
        (pa.Score * 1.0 / NULLIF(pa.ViewCount, 0)) AS ScoreToViewRatio,
        (pa.Score * 1.0 / NULLIF(pa.CommentCount, 0)) AS ScoreToCommentRatio,
        (pa.Score * 1.0 / NULLIF(pa.UpvoteCount, 0)) AS ScoreToUpvoteRatio,
        CASE 
            WHEN pa.Score > 0 AND pa.UpvoteCount > 0 THEN ((pa.UpvoteCount * 1.0 - pa.DownvoteCount) / pa.Score)
            ELSE 0 
        END AS UpvoteToDownvoteRatio,
        DATEDIFF('DAY', pa.CreationDate, CURRENT_TIMESTAMP) AS DaysSinceCreation,
        CASE 
            WHEN DATEDIFF('DAY', pa.CreationDate, CURRENT_TIMESTAMP) < 30 THEN 'New'
            WHEN DATEDIFF('DAY', pa.CreationDate, CURRENT_TIMESTAMP) < 90 THEN 'Recent'
            WHEN DATEDIFF('DAY', pa.CreationDate, CURRENT_TIMESTAMP) < 365 THEN 'Stable'
            ELSE 'Legacy'
        END AS PostAgeCategory,
        CASE 
            WHEN pa.ScorePercentile > 0.9 THEN 'Top 10%'
            WHEN pa.ScorePercentile > 0.75 THEN 'Top 25%'
            WHEN pa.ScorePercentile > 0.5 THEN 'Top 50%'
            ELSE 'Below Average'
        END AS PerformanceTier
    FROM PostAnalysis pa
),
FinalAnalysis AS (
    SELECT 
        cc.*,
        ROW_NUMBER() OVER (ORDER BY cc.Score DESC, cc.ViewCount DESC) AS FinalRank,
        (SELECT COUNT(*) FROM Posts) AS TotalPosts,
        (SELECT COUNT(*) FROM Users) AS TotalUsers,
        (SELECT COUNT(DISTINCT OwnerUserId) FROM Posts WHERE PostTypeId = 1) AS QuestionOwners,
        (SELECT COUNT(DISTINCT OwnerUserId) FROM Posts WHERE PostTypeId = 2) AS AnswerOwners,
        STRING_AGG(cc.Tags, ', ') WITHIN GROUP (ORDER BY cc.Score DESC) AS AggregatedTags,
        RANK() OVER (PARTITION BY cc.OwnerTier ORDER BY cc.Score DESC) AS TierRank,
        AVG(cc.Score) OVER (PARTITION BY cc.OwnerTier) AS AvgScoreByTier,
        COUNT(*) OVER (PARTITION BY cc.OwnerTier) AS PostCountByTier,
        (SELECT COUNT(*) FROM Users u WHERE u.Reputation > cc.OwnerReputation) AS UsersWithHigherReputation
    FROM ComplexCalculations cc
)
SELECT 
    FA.FinalRank,
    FA.PostId,
    FA.Title,
    FA.Score,
    FA.ViewCount,
    FA.OwnerDisplayName,
    FA.OwnerReputation,
    FA.OwnerTier,
    FA.ScoreCategory,
    FA.ScoreToViewRatio,
    FA.ScoreToCommentRatio,
    FA.ScoreToUpvoteRatio,
    FA.UpvoteToDownvoteRatio,
    FA.DaysSinceCreation,
    FA.PostAgeCategory,
    FA.PerformanceTier,
    FA.TierRank,
    FA.AvgScoreByTier,
    FA.PostCountByTier,
    FA.UsersWithHigherReputation,
    CASE 
        WHEN FA.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AND FA.OwnerReputation > 5000 THEN 'High Impact'
        WHEN FA.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) OR FA.OwnerReputation > 5000 THEN 'Significant'
        ELSE 'Regular'
    END AS ImpactLevel,
    CONCAT('Post-', FA.PostId, '-by-', FA.OwnerDisplayName) AS PostIdentifier,
    CAST(FA.Score AS VARCHAR) || ' points from ' || CAST(FA.ViewCount AS VARCHAR) || ' views' AS PointViewSummary,
    CASE 
        WHEN FA.ScorePercentile > 0.9 AND FA.AboveAverage = 1 THEN 'Elite Performer'
        WHEN FA.ScorePercentile > 0.75 AND FA.AboveAverage = 1 THEN 'Above Average'
        ELSE 'Standard'
    END AS PerformanceLabel
FROM FinalAnalysis FA
WHERE FA.Score > 0 
    AND (FA.OwnerReputation > 100 OR FA.OwnerTier IN ('Elite', 'Veteran'))
    AND (FA.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) OR FA.ViewCount > 1000)
ORDER BY FA.Score DESC, FA.ViewCount DESC
LIMIT 1000;