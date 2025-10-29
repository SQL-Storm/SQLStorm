-- {"query": "7646.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2359} 
WITH RankedPosts AS (
    SELECT 
        p.Id as PostId,
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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAvgScore,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAverage'
            ELSE 'Average'
        END as ScoreCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) as tag)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
                ROUND((p.AnswerCount * 100.0 / NULLIF(p.ViewCount, 0)), 2)
            ELSE NULL
        END as AnswerRate,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) as UpVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) as DownVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id),
            0
        ) as CommentCountActual
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2022-01-01 00:00:00'
      AND p.Score > 0
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount as UserViews,
        COUNT(DISTINCT rp.PostId) as TotalPosts,
        AVG(rp.Score) as AvgPostScore,
        SUM(rp.Score) as TotalScore,
        MAX(rp.CreationDate) as LastActive,
        STRING_AGG(DISTINCT rp.Title, ', ' ORDER BY rp.CreationDate) as PostTitles,
        STRING_AGG(DISTINCT rp.Tags, '; ' ORDER BY rp.CreationDate) as PostTags,
        CASE 
            WHEN COUNT(DISTINCT rp.PostId) > 0 THEN 
                (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
            ELSE 0 
        END as GoldBadges
    FROM Users u
    LEFT JOIN RankedPosts rp ON rp.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount
    HAVING COUNT(DISTINCT rp.PostId) > 0
),
PostAnalysis AS (
    SELECT 
        rp.PostId,
        rp.OwnerUserId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ScoreCategory,
        rp.TagCount,
        rp.AnswerRate,
        rp.UpVotes,
        rp.DownVotes,
        rp.CommentCountActual,
        rp.MovingAvgScore,
        rp.UserPostRank,
        rp.TotalUserPosts,
        CASE 
            WHEN rp.MovingAvgScore > rp.Score THEN 'BelowMovingAvg'
            WHEN rp.MovingAvgScore < rp.Score THEN 'AboveMovingAvg'
            ELSE 'AtMovingAvg'
        END as ScoreMovement,
        CASE 
            WHEN rp.UserPostRank = 1 THEN 'TopPost'
            WHEN rp.UserPostRank = rp.TotalUserPosts THEN 'BottomPost'
            ELSE 'MiddlePost'
        END as PostPosition,
        CASE 
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 2 THEN 'HighlyVoted'
            WHEN rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverageVoted'
            ELSE 'BelowAverageVoted'
        END as VotingLevel,
        -- Complex string expression for tag analysis
        CASE 
            WHEN rp.Tags IS NOT NULL AND rp.TagCount > 0 THEN 
                TRIM(TRAILING '><' FROM REPLACE(REPLACE(rp.Tags, '<', ''), '>', ''))
            ELSE NULL 
        END as CleanTags,
        -- Null handling and complex expression
        COALESCE(
            CASE 
                WHEN rp.Score > 0 AND rp.ViewCount > 0 THEN CAST(rp.Score AS FLOAT) / CAST(rp.ViewCount AS FLOAT) * 1000
                ELSE 0 
            END,
            0
        ) as ScorePerViewRatio
    FROM RankedPosts rp
    WHERE rp.Score > 0
),
FinalAnalysis AS (
    SELECT 
        pa.PostId,
        pa.OwnerUserId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.ScoreCategory,
        pa.TagCount,
        pa.AnswerRate,
        pa.UpVotes,
        pa.DownVotes,
        pa.CommentCountActual,
        pa.MovingAvgScore,
        pa.UserPostRank,
        pa.TotalUserPosts,
        pa.ScoreMovement,
        pa.PostPosition,
        pa.VotingLevel,
        pa.CleanTags,
        pa.ScorePerViewRatio,
        -- Correlated subquery for badge information
        (SELECT COUNT(*) 
         FROM Badges b 
         WHERE b.UserId = pa.OwnerUserId 
           AND b.Date >= pa.CreationDate 
           AND b.Class = 1) as UserGoldBadgesSincePost,
        -- Complex window function calculation
        (SUM(pa.ScorePerViewRatio) OVER (ORDER BY pa.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) / 
         NULLIF(COUNT(pa.PostId) OVER (ORDER BY pa.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW), 0)) as RollingAvgScorePerView,
        -- Set operator - union of different score categories
        CASE 
            WHEN pa.ScoreCategory IN ('AboveAverage', 'BelowAverage') 
                 AND pa.UserPostRank <= 3 
                 AND pa.AnswerRate > 5 
            THEN 'ElitePost'
            WHEN pa.VotingLevel = 'HighlyVoted' 
                 AND pa.ViewCount > 1000 
                 AND pa.AnswerCount > 5 
            THEN 'PopularPost'
            ELSE 'RegularPost'
        END as PostClassification,
        -- Outer join to get user stats
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.AvgPostScore,
        us.TotalScore,
        -- NULL handling and complex expression
        CASE 
            WHEN pa.AnswerRate IS NULL OR pa.AnswerRate = 0 THEN 'NoAnswersOrViews'
            WHEN pa.AnswerRate >= 20 THEN 'HighAnswerRate'
            WHEN pa.AnswerRate >= 10 THEN 'MediumAnswerRate'
            WHEN pa.AnswerRate >= 5 THEN 'LowAnswerRate'
            ELSE 'MinimalAnswerRate'
        END as AnswerRateCategory,
        -- Complex calculations and conditions
        CASE 
            WHEN pa.ScorePerViewRatio > (SELECT AVG(ScorePerViewRatio) FROM PostAnalysis) THEN 'AboveAveragePerformance'
            WHEN pa.ScorePerViewRatio < (SELECT AVG(ScorePerViewRatio) FROM PostAnalysis) THEN 'BelowAveragePerformance'
            ELSE 'AveragePerformance'
        END as PerformanceCategory
    FROM PostAnalysis pa
    LEFT JOIN UserStats us ON pa.OwnerUserId = us.UserId
    WHERE pa.Score > 0
      AND pa.ViewCount > 0
      AND pa.TagCount > 0
)

SELECT 
    fa.PostId,
    fa.OwnerUserId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.ScoreCategory,
    fa.TagCount,
    fa.AnswerRate,
    fa.UpVotes,
    fa.DownVotes,
    fa.CommentCountActual,
    fa.MovingAvgScore,
    fa.UserPostRank,
    fa.TotalUserPosts,
    fa.ScoreMovement,
    fa.PostPosition,
    fa.VotingLevel,
    fa.CleanTags,
    fa.ScorePerViewRatio,
    fa.UserGoldBadgesSincePost,
    fa.RollingAvgScorePerView,
    fa.PostClassification,
    fa.DisplayName,
    fa.Reputation,
    fa.TotalPosts,
    fa.AvgPostScore,
    fa.TotalScore,
    fa.AnswerRateCategory,
    fa.PerformanceCategory,
    -- Complex predicate with set operators
    CASE 
        WHEN fa.PostClassification IN ('ElitePost', 'PopularPost') 
             AND fa.Reputation >= 1000 
             AND fa.TotalPosts >= 50
        THEN 'HighPerformingUser'
        WHEN fa.PostClassification = 'RegularPost' 
             AND fa.Reputation >= 1000 
             AND fa.TotalPosts >= 50
        THEN 'StandardUser'
        ELSE 'OtherCategory'
    END as UserPerformanceCategory,
    -- String expression for generating a complex output
    CONCAT(
        'Post-', fa.PostId, 
        ' by ', COALESCE(fa.DisplayName, 'Anonymous'), 
        ' (Score:', fa.Score, 
        ', Views:', fa.ViewCount, 
        ')'
    ) as PostSummary,
    -- Final complex calculation
    ROUND(
        CASE 
            WHEN fa.AnswerRate IS NOT NULL AND fa.AnswerRate > 0 THEN 
                (fa.UpVotes + fa.DownVotes) * 100.0 / fa.AnswerRate
            ELSE 0 
        END, 2
    ) as VoteToAnswerRatio
FROM FinalAnalysis fa
WHERE fa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
  AND fa.Reputation > 500
  AND fa.TotalPosts >= 10
  AND fa.PerformanceCategory IN ('AboveAveragePerformance', 'BelowAveragePerformance')
  AND fa.PostClassification IN ('ElitePost', 'PopularPost')
ORDER BY fa.Score DESC, fa.ViewCount DESC
LIMIT 1000;