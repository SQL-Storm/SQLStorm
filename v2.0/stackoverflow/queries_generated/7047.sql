-- {"query": "7047.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2253} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Body,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as moving_avg_score,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as score_rank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.Score) as MaxPostScore,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT p.Tags, '|') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
PostAnalysis AS (
    SELECT 
        rp.Id as PostId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.Tags,
        rp.rn,
        rp.prev_score,
        rp.next_score,
        rp.moving_avg_score,
        rp.score_rank,
        CASE WHEN rp.prev_score IS NOT NULL THEN (rp.Score - rp.prev_score) ELSE 0 END as ScoreChange,
        CASE WHEN rp.next_score IS NOT NULL THEN (rp.next_score - rp.Score) ELSE 0 END as NextScoreChange,
        CASE WHEN rp.moving_avg_score > 0 THEN (rp.Score - rp.moving_avg_score) / rp.moving_avg_score ELSE 0 END as ScoreVsAvg,
        CASE WHEN rp.Score > 100 THEN 'High' 
             WHEN rp.Score > 50 THEN 'Medium' 
             ELSE 'Low' END as ScoreCategory,
        (rp.LastActivityDate - rp.CreationDate) as ActivityDuration,
        ROW_NUMBER() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.Score DESC) as TopPostRank,
        DENSE_RANK() OVER (ORDER BY rp.Score DESC) as OverallScoreRank
    FROM RankedPosts rp
),
ComplexCalculations AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.OwnerUserId,
        pa.CreationDate,
        pa.Tags,
        pa.ScoreChange,
        pa.NextScoreChange,
        pa.ScoreVsAvg,
        pa.ScoreCategory,
        pa.ActivityDuration,
        pa.TopPostRank,
        pa.OverallScoreRank,
        CASE 
            WHEN pa.ScoreChange > 10 THEN 'Consistent Growth'
            WHEN pa.ScoreChange < -10 THEN 'Consistent Decline'
            WHEN pa.ScoreVsAvg > 0.5 THEN 'Above Average'
            WHEN pa.ScoreVsAvg < -0.5 THEN 'Below Average'
            ELSE 'Normal Performance'
        END as PerformanceFlag,
        CASE 
            WHEN pa.ActivityDuration > INTERVAL '30 days' THEN 'Long Active'
            WHEN pa.ActivityDuration > INTERVAL '7 days' THEN 'Recently Active'
            ELSE 'Inactive'
        END as ActivityStatus,
        LAG(pa.Score) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) as PrevPostScore,
        LEAD(pa.Score) OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) as NextPostScore,
        CASE 
            WHEN pa.OwnerUserId IS NOT NULL AND pa.OwnerUserId > 0 THEN 
                (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = pa.OwnerUserId AND p2.PostTypeId = 1)
            ELSE 0
        END as UserQuestionCount,
        CASE 
            WHEN EXISTS (SELECT 1 FROM Posts p3 WHERE p3.ParentId = pa.PostId AND p3.PostTypeId = 2) THEN 'Has Answers'
            ELSE 'No Answers'
        END as AnswerStatus,
        COALESCE(SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags) - 2), 'No Tags') as CleanedTags,
        CASE 
            WHEN pa.ViewCount > 1000 THEN 'High Traffic'
            WHEN pa.ViewCount > 100 THEN 'Moderate Traffic'
            ELSE 'Low Traffic'
        END as TrafficCategory,
        CASE 
            WHEN pa.Score >= 50 AND pa.ViewCount >= 1000 THEN 'Popular'
            WHEN pa.Score >= 20 AND pa.ViewCount >= 500 THEN 'Notable'
            ELSE 'Regular'
        END as PopularityLevel
    FROM PostAnalysis pa
),
MainAnalysis AS (
    SELECT 
        cc.PostId,
        cc.Title,
        cc.Score,
        cc.ViewCount,
        cc.OwnerUserId,
        cc.CreationDate,
        cc.Tags,
        cc.ScoreChange,
        cc.NextScoreChange,
        cc.ScoreVsAvg,
        cc.ScoreCategory,
        cc.ActivityDuration,
        cc.TopPostRank,
        cc.OverallScoreRank,
        cc.PerformanceFlag,
        cc.ActivityStatus,
        cc.PrevPostScore,
        cc.NextPostScore,
        cc.UserQuestionCount,
        cc.AnswerStatus,
        cc.CleanedTags,
        cc.TrafficCategory,
        cc.PopularityLevel,
        CASE 
            WHEN cc.OwnerUserId > 0 THEN (SELECT DisplayName FROM Users u WHERE u.Id = cc.OwnerUserId)
            ELSE 'Anonymous'
        END as OwnerDisplayName,
        CASE 
            WHEN cc.OwnerUserId > 0 THEN (SELECT Count FROM Badges b WHERE b.UserId = cc.OwnerUserId AND b.Class = 1)
            ELSE 0
        END as GoldBadges,
        CASE 
            WHEN cc.OwnerUserId > 0 THEN (SELECT Count FROM Badges b WHERE b.UserId = cc.OwnerUserId AND b.Class = 2)
            ELSE 0
        END as SilverBadges,
        CASE 
            WHEN cc.OwnerUserId > 0 THEN (SELECT Count FROM Badges b WHERE b.UserId = cc.OwnerUserId AND b.Class = 3)
            ELSE 0
        END as BronzeBadges
    FROM ComplexCalculations cc
)
SELECT 
    ma.PostId,
    ma.Title,
    ma.Score,
    ma.ViewCount,
    ma.OwnerUserId,
    ma.CreationDate,
    ma.Tags,
    ma.ScoreChange,
    ma.NextScoreChange,
    ma.ScoreVsAvg,
    ma.ScoreCategory,
    ma.ActivityDuration,
    ma.TopPostRank,
    ma.OverallScoreRank,
    ma.PerformanceFlag,
    ma.ActivityStatus,
    ma.PrevPostScore,
    ma.NextPostScore,
    ma.UserQuestionCount,
    ma.AnswerStatus,
    ma.CleanedTags,
    ma.TrafficCategory,
    ma.PopularityLevel,
    ma.OwnerDisplayName,
    ma.GoldBadges,
    ma.SilverBadges,
    ma.BronzeBadges,
    CASE 
        WHEN ma.GoldBadges > 0 THEN 'Gold User'
        WHEN ma.SilverBadges > 0 THEN 'Silver User'
        WHEN ma.BronzeBadges > 0 THEN 'Bronze User'
        ELSE 'New User'
    END as UserLevel,
    (ma.Score * ma.ViewCount) as ScoreViewProduct,
    (ma.Score + ma.ViewCount) / NULLIF(ma.Score, 0) as ScoreViewRatio,
    ROW_NUMBER() OVER (ORDER BY ma.Score DESC) as RankByScore,
    DENSE_RANK() OVER (ORDER BY ma.ViewCount DESC) as RankByViews,
    PERCENT_RANK() OVER (ORDER BY ma.Score) as ScorePercentile,
    NTILE(10) OVER (ORDER BY ma.Score) as ScoreDecile,
    CASE 
        WHEN ma.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg Score'
        ELSE 'Below Avg Score'
    END as ScoreVsAvgComparison,
    CASE 
        WHEN ma.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg Views' 
        ELSE 'Below Avg Views'
    END as ViewsVsAvgComparison,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ma.OwnerUserId AND p.PostTypeId = 1) as UserTotalQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ma.OwnerUserId AND p.PostTypeId = 2) as UserTotalAnswers,
    EXTRACT(YEAR FROM ma.CreationDate) as PostYear,
    EXTRACT(MONTH FROM ma.CreationDate) as PostMonth,
    CONCAT(ma.Title, ' - ', ma.PopularityLevel) as TitleWithPopularity,
    CASE 
        WHEN ma.AnswerStatus = 'Has Answers' AND ma.Score > 50 THEN 1
        WHEN ma.AnswerStatus = 'No Answers' AND ma.Score > 20 THEN 1
        ELSE 0
    END as QualityIndicator
FROM MainAnalysis ma
WHERE ma.PostId IS NOT NULL
  AND ma.Score >= 0
  AND ma.ViewCount >= 0
  AND (ma.GoldBadges >= 0 OR ma.GoldBadges IS NULL)
  AND (ma.SilverBadges >= 0 OR ma.SilverBadges IS NULL)
  AND (ma.BronzeBadges >= 0 OR ma.BronzeBadges IS NULL)
  AND (ma.UserQuestionCount >= 0 OR ma.UserQuestionCount IS NULL)
  AND ma.PostId > 0
ORDER BY ma.Score DESC, ma.ViewCount DESC
LIMIT 10000;