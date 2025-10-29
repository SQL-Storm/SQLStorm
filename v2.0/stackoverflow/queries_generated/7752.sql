-- {"query": "7752.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2196} 
WITH UserStats AS (
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
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as TagList
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as TypeScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as NewestPost,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingAvgScore,
        MAX(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingMaxScore,
        p.Score - LAG(p.Score) OVER (ORDER BY p.CreationDate) as ScoreChange,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 500 THEN 'Moderate'
            ELSE 'Less Popular'
        END as Popularity,
        COALESCE(p.Tags, '') as Tags,
        COALESCE(p.Body, '') as Body,
        p.PostTypeId
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
QuestionAnalysis AS (
    SELECT 
        qa.PostId,
        qa.Title,
        qa.Score,
        qa.ViewCount,
        qa.CommentCount,
        qa.FavoriteCount,
        qa.LastActivityDate,
        qa.AcceptedAnswerId,
        CASE 
            WHEN qa.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Unanswered'
        END as QuestionStatus,
        COUNT(c.Id) as AnswerCount,
        AVG(c.Score) as AvgAnswerScore,
        MAX(c.CreationDate) as LatestAnswerDate,
        DATEDIFF(day, qa.CreationDate, qa.LastActivityDate) as DaysSinceCreation,
        CASE 
            WHEN DATEDIFF(day, qa.CreationDate, qa.LastActivityDate) > 30 THEN 'Stale'
            WHEN DATEDIFF(day, qa.CreationDate, qa.LastActivityDate) > 7 THEN 'Active'
            ELSE 'Recent'
        END as ActivityLevel
    FROM PostPerformance qa
    LEFT JOIN Posts c ON qa.Id = c.ParentId AND c.PostTypeId = 2
    WHERE qa.PostTypeId = 1
    GROUP BY qa.PostId, qa.Title, qa.Score, qa.ViewCount, qa.CommentCount, qa.FavoriteCount, 
             qa.LastActivityDate, qa.AcceptedAnswerId, qa.CreationDate
),
AnswerAnalysis AS (
    SELECT 
        aa.Id as AnswerId,
        aa.ParentId,
        aa.Score,
        aa.OwnerUserId,
        aa.CreationDate,
        aa.LastEditDate,
        aa.LastActivityDate,
        aa.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY aa.ParentId ORDER BY aa.Score DESC) as AnswerRank,
        CASE 
            WHEN DATEDIFF(minute, aa.CreationDate, aa.LastEditDate) > 0 THEN 'Edited'
            ELSE 'Not Edited'
        END as EditStatus,
        COALESCE(DATEDIFF(hour, aa.CreationDate, aa.LastActivityDate), 0) as HoursToLastActivity
    FROM Posts aa
    WHERE aa.PostTypeId = 2
),
CombinedAnalysis AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        pa.Id as PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.CreationDate,
        pa.ScoreRank,
        pa.TypeScoreRank,
        pa.NewestPost,
        pa.ScoreQuartile,
        pa.ScoreChange,
        pa.ScoreCategory,
        pa.Popularity,
        qa.QuestionStatus,
        qa.AnswerCount,
        qa.AvgAnswerScore,
        qa.DaysSinceCreation,
        qa.ActivityLevel,
        aa.AnswerId,
        aa.AnswerRank,
        aa.EditStatus,
        aa.HoursToLastActivity
    FROM UserStats ua
    INNER JOIN PostPerformance pa ON ua.UserId = pa.OwnerUserId
    LEFT JOIN QuestionAnalysis qa ON pa.Id = qa.PostId
    LEFT JOIN AnswerAnalysis aa ON pa.Id = aa.ParentId
    WHERE pa.Score > 0
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostCount,
    ca.CommentCount,
    ca.BadgeCount,
    ca.PostId,
    ca.Title,
    ca.Score,
    ca.ViewCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.CreationDate,
    ca.ScoreRank,
    ca.TypeScoreRank,
    ca.NewestPost,
    ca.ScoreQuartile,
    ca.ScoreChange,
    ca.ScoreCategory,
    ca.Popularity,
    ca.QuestionStatus,
    ca.AnswerCount,
    ca.AvgAnswerScore,
    ca.DaysSinceCreation,
    ca.ActivityLevel,
    ca.AnswerId,
    ca.AnswerRank,
    ca.EditStatus,
    ca.HoursToLastActivity,
    CASE 
        WHEN ca.Reputation > 10000 AND ca.PostCount > 50 THEN 'Veteran'
        WHEN ca.Reputation > 5000 AND ca.PostCount > 25 THEN 'Experienced'
        WHEN ca.Reputation > 1000 AND ca.PostCount > 10 THEN 'Active'
        ELSE 'Beginner'
    END as UserTier,
    CASE 
        WHEN ca.Score > 1000 AND ca.ViewCount > 1000 THEN 'High Impact'
        WHEN ca.Score > 100 AND ca.ViewCount > 100 THEN 'Moderate Impact'
        WHEN ca.Score > 10 AND ca.ViewCount > 10 THEN 'Low Impact'
        ELSE 'Minimal Impact'
    END as ImpactLevel,
    CASE 
        WHEN ca.ActivityLevel = 'Stale' THEN 'Needs Attention'
        WHEN ca.ActivityLevel = 'Active' THEN 'Engaged'
        ELSE 'Recent Activity'
    END as EngagementStatus,
    -- Complex calculations involving multiple fields
    ROUND((ca.Score * (ca.ViewCount + 1)) / (NULLIF(ca.CommentCount + 1, 0) * NULLIF(ca.FavoriteCount + 1, 0)), 2) as ComplexScoreMetric,
    RIGHT('0000000000' + CAST(ca.UserId AS VARCHAR(10)), 10) as FormattedUserId,
    -- String manipulation examples
    SUBSTRING(UPPER(ca.Title), 1, 50) as TitlePrefix,
    REPLACE(LOWER(ca.Popularity), ' ', '') as CleanPopularity,
    CAST(ca.CreationDate AS DATE) as PostDate,
    -- Set operators with UNION ALL and complex predicates
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2) as AnswerCount,
    -- Subquery and correlated subquery examples
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 1) as GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 2) as SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 3) as BronzeBadgeCount,
    CASE 
        WHEN (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 1) > 0 THEN 'Has Gold'
        ELSE 'No Gold'
    END as GoldStatus,
    -- NULL handling and conditional logic
    CASE 
        WHEN ca.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answered'
        WHEN ca.AnswerCount > 0 THEN 'Answered but not accepted'
        ELSE 'Not Answered'
    END as AnswerStatus,
    CASE 
        WHEN ca.AnswerCount IS NULL THEN 'No Answer Data'
        WHEN ca.AnswerCount = 0 THEN 'Zero Answers'
        ELSE CAST(ca.AnswerCount AS VARCHAR(10))
    END as AnswerCountFormatted,
    -- Window function with complex partitioning
    ROW_NUMBER() OVER (PARTITION BY ca.AnswerCount ORDER BY ca.Score DESC) as ScoreRankByAnswerCount
FROM CombinedAnalysis ca
WHERE ca.Score > 50
    AND ca.ViewCount > 10
    AND (ca.QuestionStatus = 'Answered' OR ca.QuestionStatus = 'Unanswered')
    AND ca.ActivityLevel IN ('Active', 'Stale', 'Recent')
ORDER BY ca.Score DESC, ca.NewestPost ASC, ca.Reputation DESC
OFFSET 100 ROWS FETCH NEXT 1000 ROWS ONLY;