-- {"query": "29062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2237} 
WITH UserActivityStats AS (
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
        MAX(c.CreationDate) as LastCommentDate,
        CASE 
            WHEN u.Reputation < 100 THEN 'Novice'
            WHEN u.Reputation BETWEEN 100 AND 999 THEN 'Contributor'
            WHEN u.Reputation BETWEEN 1000 AND 9999 THEN 'Expert'
            ELSE 'Master'
        END as ReputationTier,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgPostScore,
        STDEV(p.Score) as ScoreStdDev
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p1.ViewCount, 0) as ExcerptViews,
        COALESCE(p2.ViewCount, 0) as WikiViews,
        CASE 
            WHEN t.Count > 100 THEN 'Highly Popular'
            WHEN t.Count > 50 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity
    FROM Tags t
    LEFT JOIN Posts p1 ON t.ExcerptPostId = p1.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
    WHERE t.TagName IS NOT NULL
),
QuestionAnalysis AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        CASE 
            WHEN p.AnswerCount = 0 THEN 'No Answers'
            WHEN p.AnswerCount = 1 THEN 'One Answer'
            WHEN p.AnswerCount <= 5 THEN 'Few Answers'
            ELSE 'Many Answers'
        END as AnswerDensity,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as DaysSinceCreation,
        p.Score - LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as ScoreChange,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserQuestionSequence,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 25 THEN 'Well Voted'
            WHEN p.Score > 0 THEN 'Neutral'
            ELSE 'Lowly Voted'
        END as VoteStatus,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 100 THEN 'Popular'
            WHEN p.ViewCount > 10 THEN 'Moderate'
            ELSE 'Low'
        END as ViewStatus
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerDistribution AS (
    SELECT 
        a.ParentId,
        COUNT(*) as AnswerCount,
        AVG(a.Score) as AvgAnswerScore,
        MAX(a.Score) as MaxAnswerScore,
        MIN(a.Score) as MinAnswerScore,
        SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) as PositiveAnswers,
        SUM(CASE WHEN a.Score < 0 THEN 1 ELSE 0 END) as NegativeAnswers,
        SUM(CASE WHEN a.Score = 0 THEN 1 ELSE 0 END) as NeutralAnswers,
        (SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) as PositiveRatio,
        STRING_AGG(CASE WHEN a.Score > 0 THEN a.OwnerDisplayName ELSE NULL END, ', ') as TopScoringAuthors
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
ComplexQueryResults AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.ReputationTier,
        ua.TotalScore,
        ua.AvgPostScore,
        ua.ScoreStdDev,
        t.TagName,
        t.TagCount,
        t.TagPopularity,
        q.QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        q.AnswerDensity,
        q.VoteStatus,
        q.ViewStatus,
        ad.AnswerCount as RelatedAnswerCount,
        ad.AvgAnswerScore,
        ad.PositiveRatio,
        CASE 
            WHEN q.Score > 0 AND q.ViewCount > 100 THEN 1
            WHEN q.Score <= 0 AND q.ViewCount <= 10 THEN 0
            ELSE -1
        END as QualityClassification,
        CASE 
            WHEN u.Views IS NOT NULL THEN 'Active User'
            WHEN u.Views IS NULL THEN 'Inactive User'
            ELSE 'Unknown'
        END as ActivityStatus,
        CASE 
            WHEN q.DaysSinceCreation <= 30 THEN 'New'
            WHEN q.DaysSinceCreation <= 90 THEN 'Recent'
            ELSE 'Old'
        END as QuestionAge,
        DENSE_RANK() OVER (ORDER BY q.Score DESC) as ScoreRank,
        NTILE(4) OVER (ORDER BY q.ViewCount DESC) as ViewQuartile,
        PERCENT_RANK() OVER (ORDER BY ua.TotalScore DESC) as ScorePercentile,
        LAG(q.Score) OVER (ORDER BY q.CreationDate) as PrevQuestionScore,
        LEAD(q.Score) OVER (ORDER BY q.CreationDate) as NextQuestionScore,
        COALESCE(
            CASE 
                WHEN q.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 1
                ELSE 0
            END,
            0
        ) as AboveAverageScore,
        COALESCE(
            CASE 
                WHEN q.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 1
                ELSE 0
            END,
            0
        ) as AboveAverageViews,
        CASE 
            WHEN q.Tags IS NOT NULL AND LENGTH(q.Tags) > 0 THEN 
                CONCAT('Tagged with: ', SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2))
            ELSE 'No Tags'
        END as TagInfo,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.PostId = q.QuestionId 
             AND v.VoteTypeId IN (2, 3)), 0
        ) as TotalVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c 
             WHERE c.PostId = q.QuestionId), 0
        ) as CommentCountOnQuestion,
        CASE 
            WHEN q.AnswerCount > 0 AND q.AnswerCount = (
                SELECT COUNT(*) 
                FROM Posts p2 
                WHERE p2.ParentId = q.QuestionId 
                AND p2.PostTypeId = 2
            ) THEN 'All Answers Present'
            ELSE 'Some Answers Missing'
        END as AnswerCompleteness,
        CASE 
            WHEN q.OwnerUserId IN (
                SELECT DISTINCT UserId 
                FROM Badges 
                WHERE Name IN ('Populist', 'Great Question', 'Good Question')
            ) THEN 'Awarded Question'
            ELSE 'Regular Question'
        END as QuestionAwardStatus,
        COALESCE(q.Score - q.UserAvgScore, 0) as ScoreVsUserAvg,
        ABS(q.AnswerCount - COALESCE(ad.AnswerCount, 0)) as AnswerCountDelta,
        TRIM(BOTH '<>' FROM q.Tags) as CleanedTags
    FROM UserActivityStats ua
    INNER JOIN Users u ON ua.UserId = u.Id
    LEFT JOIN TagPerformance t ON ua.ReputationTier LIKE '%Contributor%'
    LEFT JOIN QuestionAnalysis q ON ua.UserId = q.OwnerUserId
    LEFT JOIN AnswerDistribution ad ON q.QuestionId = ad.ParentId
    WHERE ua.Reputation > 0
    AND ua.PostCount > 0
    AND q.QuestionId IS NOT NULL
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    CommentCount,
    BadgeCount,
    ReputationTier,
    TotalScore,
    AvgPostScore,
    ScoreStdDev,
    TagName,
    TagCount,
    TagPopularity,
    QuestionId,
    Title,
    QuestionScore,
    QuestionViews,
    AnswerCount,
    AnswerDensity,
    VoteStatus,
    ViewStatus,
    RelatedAnswerCount,
    AvgAnswerScore,
    PositiveRatio,
    QualityClassification,
    ActivityStatus,
    QuestionAge,
    ScoreRank,
    ViewQuartile,
    ScorePercentile,
    PrevQuestionScore,
    NextQuestionScore,
    AboveAverageScore,
    AboveAverageViews,
    TagInfo,
    TotalVotes,
    CommentCountOnQuestion,
    AnswerCompleteness,
    QuestionAwardStatus,
    ScoreVsUserAvg,
    AnswerCountDelta,
    CleanedTags,
    CASE 
        WHEN AVG(QuestionScore) OVER (PARTITION BY UserId) > 10 THEN 'High Performing User'
        WHEN AVG(QuestionScore) OVER (PARTITION BY UserId) > 5 THEN 'Medium Performing User'
        ELSE 'Low Performing User'
    END as UserPerformanceCategory
FROM ComplexQueryResults
WHERE TagCount > 10
AND QuestionScore > -10
AND QuestionViews > 0
AND PostCount >= 5
ORDER BY ScoreRank, ViewQuartile, AnswerCountDelta ASC NULLS LAST
LIMIT 20000;