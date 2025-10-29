-- {"query": "7023.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2208} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId) 
            THEN 'AboveAvg' 
            ELSE 'BelowAvg' 
        END as ScoreCategory,
        COALESCE(p.Title, '') || ' - ' || COALESCE(p.Tags, '') as TitleTagConcat,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5)
            ELSE 0 
        END as HighScoreComments
    FROM Posts p
    WHERE p.CreationDate >= '2022-01-01' 
      AND p.PostTypeId IN (1, 2)
),
PostActivityStats AS (
    SELECT 
        r.Id,
        r.OwnerUserId,
        r.Score,
        r.ScoreRank,
        r.UserPostSequence,
        r.PrevScore,
        r.NextScore,
        r.AvgScoreByType,
        r.ScoreCategory,
        r.TitleTagConcat,
        r.HighScoreComments,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.Id AND v.VoteTypeId IN (2, 3)),
            0
        ) as TotalVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.Id AND v.VoteTypeId = 5),
            0
        ) as FavoriteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.Id),
            0
        ) as CommentCount,
        CASE 
            WHEN r.Score < 0 THEN 'Negative'
            WHEN r.Score BETWEEN 0 AND 10 THEN 'Low'
            WHEN r.Score BETWEEN 11 AND 50 THEN 'Medium'
            WHEN r.Score > 50 THEN 'High'
            ELSE 'Unknown'
        END as ScoreTier,
        CASE 
            WHEN r.AnswerCount > 0 THEN (
                SELECT COUNT(*) 
                FROM Posts a 
                WHERE a.ParentId = r.Id 
                  AND a.PostTypeId = 2 
                  AND a.Score > 10
            )
            ELSE 0
        END as HighQualityAnswers
    FROM RankedPosts r
),
UserEngagementStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LatestPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1),
            0
        ) as GoldBadges,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2),
            0
        ) as SilverBadges,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3),
            0
        ) as BronzeBadges,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2022-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
ComplexMetrics AS (
    SELECT 
        pas.Id,
        pas.OwnerUserId,
        pas.Score,
        pas.ScoreRank,
        pas.UserPostSequence,
        pas.PrevScore,
        pas.NextScore,
        pas.AvgScoreByType,
        pas.ScoreCategory,
        pas.TitleTagConcat,
        pas.HighScoreComments,
        pas.TotalVotes,
        pas.FavoriteCount,
        pas.CommentCount,
        pas.ScoreTier,
        pas.HighQualityAnswers,
        ues.DisplayName,
        ues.Reputation,
        ues.Views,
        ues.UpVotes,
        ues.DownVotes,
        ues.TotalPosts,
        ues.TotalScore,
        ues.AvgScore,
        ues.LatestPostDate,
        ues.QuestionCount,
        ues.AnswerCount,
        ues.GoldBadges,
        ues.SilverBadges,
        ues.BronzeBadges,
        ues.UserTier,
        CASE 
            WHEN pas.Score > ues.AvgScore AND pas.Score > 0 THEN 'AboveUserAvg'
            WHEN pas.Score < ues.AvgScore AND pas.Score > 0 THEN 'BelowUserAvg'
            ELSE 'AtUserAvg'
        END as RelativeScoreToUser,
        IIF(pas.UserPostSequence = 1, 0, 
            (pas.Score - pas.PrevScore) / NULLIF(pas.PrevScore, 0) * 100.0
        ) as ScoreChangePercent,
        CASE 
            WHEN ues.TotalPosts > 100 THEN 'HighVolume'
            WHEN ues.TotalPosts > 50 THEN 'MediumVolume'
            WHEN ues.TotalPosts > 10 THEN 'LowVolume'
            ELSE 'VeryLowVolume'
        END as ActivityLevel,
        IIF(pas.Score > 0 AND pas.TotalVotes > 0, 
            CAST(pas.Score AS FLOAT) * 100 / NULLIF(pas.TotalVotes, 0),
            0
        ) as ScorePerVote,
        LTRIM(RTRIM(
            LEFT(pas.TitleTagConcat, 
                 CASE 
                     WHEN LEN(pas.TitleTagConcat) > 100 THEN 100
                     ELSE LEN(pas.TitleTagConcat)
                 END
            )
        )) as ShortTitleTag,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph 
             WHERE ph.PostId = pas.Id 
               AND ph.PostHistoryTypeId IN (1, 4, 6) 
               AND ph.CreationDate > '2022-01-01'),
            0
        ) as EditCount,
        IIF(pas.Score > 50 AND pas.CommentCount > 10, 'HighlyEngaged', 'RegularUser') as EngagementFlag,
        CASE 
            WHEN (DATEDIFF(day, ues.CreationDate, GETDATE()) / 30.0) > 12 THEN 'Experienced'
            WHEN (DATEDIFF(day, ues.CreationDate, GETDATE()) / 30.0) > 6 THEN 'Intermediate'
            ELSE 'EarlyStage'
        END as ExperienceLevel
    FROM PostActivityStats pas
    INNER JOIN UserEngagementStats ues ON pas.OwnerUserId = ues.UserId
    WHERE pas.Score IS NOT NULL 
      AND ues.Reputation > 100
)
SELECT 
    cm.Id,
    cm.OwnerUserId,
    cm.Score,
    cm.ScoreRank,
    cm.UserPostSequence,
    cm.PrevScore,
    cm.NextScore,
    cm.AvgScoreByType,
    cm.ScoreCategory,
    cm.TitleTagConcat,
    cm.HighScoreComments,
    cm.TotalVotes,
    cm.FavoriteCount,
    cm.CommentCount,
    cm.ScoreTier,
    cm.HighQualityAnswers,
    cm.DisplayName,
    cm.Reputation,
    cm.Views,
    cm.UpVotes,
    cm.DownVotes,
    cm.TotalPosts,
    cm.TotalScore,
    cm.AvgScore,
    cm.LatestPostDate,
    cm.QuestionCount,
    cm.AnswerCount,
    cm.GoldBadges,
    cm.SilverBadges,
    cm.BronzeBadges,
    cm.UserTier,
    cm.RelativeScoreToUser,
    cm.ScoreChangePercent,
    cm.ActivityLevel,
    cm.ScorePerVote,
    cm.ShortTitleTag,
    cm.EditCount,
    cm.EngagementFlag,
    cm.ExperienceLevel,
    CASE 
        WHEN cm.ScorePerVote > 50.0 AND cm.Score > 100 THEN 'VeryHighValue'
        WHEN cm.ScorePerVote > 25.0 AND cm.Score > 50 THEN 'HighValue'
        WHEN cm.ScorePerVote > 10.0 AND cm.Score > 20 THEN 'MediumValue'
        ELSE 'LowValue'
    END as ValueCategory,
    IIF(cm.Score > 100 AND cm.HighQualityAnswers > 5, 'ExpertContributor', 'RegularContributor') as ContributionLevel,
    ROW_NUMBER() OVER (ORDER BY cm.Score DESC) as OverallRank,
    PERCENT_RANK() OVER (ORDER BY cm.Reputation) as ReputationPercentile
FROM ComplexMetrics cm
WHERE cm.Score > 0
  AND cm.TotalVotes > 0
  AND cm.AnswerCount > 0
  AND cm.Score > (
    SELECT AVG(Score) 
    FROM ComplexMetrics cm2 
    WHERE cm2.OwnerUserId = cm.OwnerUserId
  )
ORDER BY cm.Score DESC, cm.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 10000 ROWS ONLY;