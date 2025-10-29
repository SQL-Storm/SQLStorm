-- {"query": "7618.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2117} 
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RowNum,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScore,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
            ELSE 0
        END as TagCount,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
),
UserActivity AS (
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
        COALESCE(SUM(p.Score), 0) as TotalScore,
        AVG(p.Score) as AvgPostScore,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        CASE 
            WHEN u.Views > 100000 THEN 'Popular'
            WHEN u.Views > 10000 THEN 'Notable'
            WHEN u.Views > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as PopularityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        rp.Id as PostId,
        rp.Title,
        rp.Score,
        rp.TagCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.ScoreCategory,
        rp.DaysOpen,
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalScore,
        ua.AvgPostScore,
        ua.ReputationLevel,
        ua.PopularityLevel,
        CASE 
            WHEN rp.Score > ua.AvgPostScore THEN 'Above Average'
            WHEN rp.Score > ua.AvgPostScore * 0.8 THEN 'Near Average'
            ELSE 'Below Average'
        END as PerformanceLevel,
        CASE 
            WHEN rp.Score >= 100 OR rp.AnswerCount >= 5 THEN TRUE
            ELSE FALSE
        END as HighQualityIndicator,
        CASE 
            WHEN rp.DaysOpen > 30 
                AND rp.Score < 10 
                AND rp.CommentCount < 2 
                AND rp.AnswerCount < 1 THEN 'Stale'
            WHEN rp.DaysOpen < 7 AND rp.Score > 50 THEN 'Hot'
            WHEN rp.Tags IS NULL OR rp.Tags = '' THEN 'Untagged'
            ELSE 'Normal'
        END as PostStatus
    FROM RankedPosts rp
    INNER JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.RowNum = 1  -- Only latest post per user
),
ComplexAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.TagCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.ScoreCategory,
        pa.DaysOpen,
        pa.UserId,
        pa.DisplayName,
        pa.Reputation,
        pa.TotalScore,
        pa.AvgPostScore,
        pa.ReputationLevel,
        pa.PopularityLevel,
        pa.PerformanceLevel,
        pa.HighQualityIndicator,
        pa.PostStatus,
        LAG(pa.Score) OVER (ORDER BY pa.Score DESC) as PreviousScore,
        NTH_VALUE(pa.Score, 10) OVER (ORDER BY pa.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as Score10thPercentile,
        (pa.Score - AVG(pa.Score) OVER ()) / STDDEV(pa.Score) OVER() as ZScore,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = pa.UserId AND p2.PostTypeId = 1) as UserQuestionCount,
        (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = pa.UserId AND p3.PostTypeId = 2) as UserAnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 3) as Downvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.PostId) as CommentCountOnPost,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = pa.UserId AND b.Class = 1), 
            0
        ) as GoldBadges,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = pa.UserId AND b.Class = 2), 
            0
        ) as SilverBadges,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = pa.UserId AND b.Class = 3), 
            0
        ) as BronzeBadges
    FROM PostAnalysis pa
),
FinalAnalysis AS (
    SELECT 
        ca.PostId,
        ca.Title,
        ca.Score,
        ca.TagCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.ScoreCategory,
        ca.DaysOpen,
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.TotalScore,
        ca.AvgPostScore,
        ca.ReputationLevel,
        ca.PopularityLevel,
        ca.PerformanceLevel,
        ca.HighQualityIndicator,
        ca.PostStatus,
        ca.PreviousScore,
        ca.Score10thPercentile,
        ROUND(ca.ZScore, 2) as ZScore,
        ca.UserQuestionCount,
        ca.UserAnswerCount,
        ca.Upvotes,
        ca.Downvotes,
        ca.CommentCountOnPost,
        ca.GoldBadges,
        ca.SilverBadges,
        ca.BronzeBadges,
        CASE 
            WHEN ca.ZScore > 2 THEN 'Exceptional'
            WHEN ca.ZScore > 1 THEN 'Strong'
            WHEN ca.ZScore > 0 THEN 'Moderate'
            WHEN ca.ZScore > -1 THEN 'Weak'
            ELSE 'Poor'
        END as PerformanceTier,
        CASE 
            WHEN ca.TagCount > 3 THEN 'Well Tagged'
            WHEN ca.TagCount = 0 THEN 'Untagged'
            ELSE 'Moderately Tagged'
        END as TaggingQuality,
        CASE 
            WHEN ca.UserQuestionCount > 100 THEN 'Veteran'
            WHEN ca.UserQuestionCount > 50 THEN 'Experienced'
            WHEN ca.UserQuestionCount > 10 THEN 'Active'
            ELSE 'Casual'
        END as UserActivityLevel,
        ROW_NUMBER() OVER (ORDER BY ca.Score DESC) as RankByScore,
        DENSE_RANK() OVER (PARTITION BY ca.ReputationLevel ORDER BY ca.Score DESC) as ReputationRank
    FROM ComplexAnalysis ca
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.TagCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.ScoreCategory,
    fa.DaysOpen,
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.TotalScore,
    fa.AvgPostScore,
    fa.ReputationLevel,
    fa.PopularityLevel,
    fa.PerformanceLevel,
    fa.HighQualityIndicator,
    fa.PostStatus,
    fa.PreviousScore,
    fa.Score10thPercentile,
    fa.ZScore,
    fa.UserQuestionCount,
    fa.UserAnswerCount,
    fa.Upvotes,
    fa.Downvotes,
    fa.CommentCountOnPost,
    fa.GoldBadges,
    fa.SilverBadges,
    fa.BronzeBadges,
    fa.PerformanceTier,
    fa.TaggingQuality,
    fa.UserActivityLevel,
    fa.RankByScore,
    fa.ReputationRank
FROM FinalAnalysis fa
WHERE fa.Score > 0 
    AND fa.Reputation > 100
    AND fa.PostStatus IN ('Hot', 'Normal', 'Stale')
    AND (
        fa.TaggingQuality IN ('Well Tagged', 'Moderately Tagged')
        OR fa.PostStatus IN ('Hot')
    )
ORDER BY 
    CASE 
        WHEN fa.PerformanceTier = 'Exceptional' THEN 1
        WHEN fa.PerformanceTier = 'Strong' THEN 2
        WHEN fa.PerformanceTier = 'Moderate' THEN 3
        WHEN fa.PerformanceTier = 'Weak' THEN 4
        WHEN fa.PerformanceTier = 'Poor' THEN 5
        ELSE 6
    END,
    fa.Score DESC,
    fa.Reputation DESC,
    fa.RankByScore ASC
LIMIT 1000 OFFSET 0;