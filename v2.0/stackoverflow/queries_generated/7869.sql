-- {"query": "7869.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3057} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Question with answers'
            WHEN p.PostTypeId = 1 THEN 'Question without answers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTILE(100) OVER (ORDER BY p.Score) as ScoreQuartile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        COALESCE(p.Tags, '') as CleanTags
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
ComplexJoinAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.OwnerUserId,
        pa.PostCategory,
        pa.ScoreRank,
        pa.ViewRank,
        pa.ScorePercentile,
        pa.ScoreQuartile,
        pa.PrevScore,
        pa.NextScore,
        pa.CleanTags,
        u.DisplayName as AuthorName,
        u.Reputation as AuthorReputation,
        u.ViewCount as AuthorViews,
        CASE 
            WHEN pa.AnswerCount > 0 THEN 
                (SELECT AVG(AnswerScore) FROM (
                    SELECT p2.Score as AnswerScore 
                    FROM Posts p2 
                    WHERE p2.ParentId = pa.PostId 
                    AND p2.PostTypeId = 2
                ) answers)
            ELSE NULL 
        END as AverageAnswerScore,
        CASE 
            WHEN pa.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts p3 WHERE p3.ParentId = pa.PostId AND p3.PostTypeId = 2)
            ELSE 0 
        END as AnswerCount,
        COALESCE(
            (SELECT TOP 1 bh.Comment FROM PostHistory bh 
             WHERE bh.PostId = pa.PostId 
             AND bh.PostHistoryTypeId = 10 
             AND bh.Comment IS NOT NULL 
             AND bh.Comment != ''),
            'No close reason'
        ) as CloseReason,
        (SELECT COUNT(*) FROM Votes v 
         WHERE v.PostId = pa.PostId 
         AND v.VoteTypeId IN (2, 3)) as VoteCount,
        (SELECT COUNT(*) FROM Comments c 
         WHERE c.PostId = pa.PostId) as CommentCount,
        IIF(pa.ViewCount > 1000, 'High Traffic', 'Normal Traffic') as TrafficLevel,
        CASE 
            WHEN pa.Score > 100 THEN 'Highly Voted'
            WHEN pa.Score > 50 THEN 'Moderately Voted'
            WHEN pa.Score > 0 THEN 'Slightly Voted'
            ELSE 'Not Voted'
        END as VoteStatus,
        DATEPART(YEAR, pa.CreationDate) as YearPosted,
        DATEPART(MONTH, pa.CreationDate) as MonthPosted,
        CASE 
            WHEN pa.Tags LIKE '%<javascript>%' THEN 'JavaScript'
            WHEN pa.Tags LIKE '%<python>%' THEN 'Python'
            WHEN pa.Tags LIKE '%<java>%' THEN 'Java'
            WHEN pa.Tags LIKE '%<c#>%' THEN 'C#'
            ELSE 'Other'
        END as PrimaryLanguage,
        (SELECT COUNT(DISTINCT UserId) FROM PostHistory ph 
         WHERE ph.PostId = pa.PostId 
         AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditCount,
        CASE 
            WHEN pa.LastActivityDate >= DATEADD(DAY, -30, GETDATE()) THEN 'Active'
            ELSE 'Inactive'
        END as ActivityStatus
    FROM PostAnalysis pa
    INNER JOIN Users u ON pa.OwnerUserId = u.Id
    WHERE pa.PostCategory IN ('Question with answers', 'Question without answers', 'Answer')
),
FinalAnalysis AS (
    SELECT 
        cja.PostId,
        cja.Title,
        cja.Score,
        cja.ViewCount,
        cja.OwnerUserId,
        cja.AuthorName,
        cja.AuthorReputation,
        cja.AuthorViews,
        cja.PostCategory,
        cja.ScoreRank,
        cja.ViewRank,
        cja.ScorePercentile,
        cja.ScoreQuartile,
        cja.AverageAnswerScore,
        cja.AnswerCount,
        cja.CloseReason,
        cja.VoteCount,
        cja.CommentCount,
        cja.TrafficLevel,
        cja.VoteStatus,
        cja.YearPosted,
        cja.MonthPosted,
        cja.PrimaryLanguage,
        cja.EditCount,
        cja.ActivityStatus,
        ROW_NUMBER() OVER (ORDER BY cja.Score DESC) as OverallRank,
        RANK() OVER (PARTITION BY cja.PrimaryLanguage ORDER BY cja.Score DESC) as LanguageRank,
        DENSE_RANK() OVER (ORDER BY cja.YearPosted, cja.MonthPosted) as TimeRank,
        (CASE 
            WHEN cja.VoteCount > 100 THEN 'Highly Engaged'
            WHEN cja.VoteCount > 50 THEN 'Moderately Engaged'
            WHEN cja.VoteCount > 10 THEN 'Slightly Engaged'
            ELSE 'Not Engaged'
        END) as EngagementLevel,
        CASE 
            WHEN cja.Score > 100 AND cja.ViewCount > 1000 THEN 1
            WHEN cja.Score > 50 AND cja.ViewCount > 500 THEN 2
            WHEN cja.Score > 10 AND cja.ViewCount > 100 THEN 3
            ELSE 4
        END as QualityLevel,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = cja.OwnerUserId 
         AND p.PostTypeId = 1 
         AND p.CreationDate >= DATEADD(YEAR, -1, GETDATE())) as RecentQuestions,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = cja.OwnerUserId 
         AND p.PostTypeId = 2 
         AND p.CreationDate >= DATEADD(YEAR, -1, GETDATE())) as RecentAnswers,
        ISNULL(cja.AuthorReputation / NULLIF(cja.AuthorViews, 0), 0) as RepPerView,
        CASE 
            WHEN cja.AnswerCount > 0 AND cja.Score > 10 THEN 'Quality Question'
            WHEN cja.AnswerCount = 0 AND cja.Score > 10 THEN 'Good Question'
            WHEN cja.Score > 10 THEN 'Highly Voted Post'
            ELSE 'Regular Post'
        END as PostQuality,
        IIF(cja.Score = 0, 'No Votes', 
            IIF(cja.Score > 0, 'Positive Votes', 'Negative Votes')) as VoteDirection,
        -- This is the complex expression part: a calculation of a complex metric
        CAST(
            (cja.Score * 2 + 
             cja.ViewCount * 0.1 + 
             ISNULL(cja.AverageAnswerScore, 0) * 3 + 
             cja.AnswerCount * 5 +
             cja.VoteCount * 0.5) 
            AS DECIMAL(10,2)
        ) as ComplexMetric,
        ABS(cja.Score - ISNULL(cja.PrevScore, 0)) as ScoreChange,
        ABS(cja.Score - ISNULL(cja.NextScore, 0)) as NextScoreChange
    FROM ComplexJoinAnalysis cja
    WHERE cja.Score <> 0 OR cja.ViewCount > 0 OR cja.AnswerCount > 0
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.OwnerUserId,
    fa.AuthorName,
    fa.PostCategory,
    fa.ScoreRank,
    fa.ViewRank,
    fa.ScorePercentile,
    fa.ScoreQuartile,
    fa.AverageAnswerScore,
    fa.AnswerCount,
    fa.VoteCount,
    fa.CommentCount,
    fa.TrafficLevel,
    fa.VoteStatus,
    fa.YearPosted,
    fa.MonthPosted,
    fa.PrimaryLanguage,
    fa.EditCount,
    fa.ActivityStatus,
    fa.OverallRank,
    fa.LanguageRank,
    fa.TimeRank,
    fa.EngagementLevel,
    fa.QualityLevel,
    fa.RecentQuestions,
    fa.RecentAnswers,
    fa.RepPerView,
    fa.PostQuality,
    fa.VoteDirection,
    fa.ComplexMetric,
    fa.ScoreChange,
    fa.NextScoreChange,
    -- The main complex predicate logic
    CASE 
        WHEN fa.ComplexMetric > 100 AND fa.RecentQuestions > 0 
        AND fa.RecentAnswers > 0 AND fa.Score > 50 
        THEN 'Top Performer'
        WHEN fa.ComplexMetric > 50 AND fa.RecentQuestions > 0 
        AND fa.RecentAnswers > 0 AND fa.Score > 25 
        THEN 'Good Performer'
        WHEN fa.ComplexMetric > 25 AND fa.RecentQuestions > 0 
        AND fa.RecentAnswers > 0 AND fa.Score > 0 
        THEN 'Average Performer'
        ELSE 'Below Average'
    END as PerformanceCategory,
    -- Using set operators to combine different categories
    CASE 
        WHEN COUNT(*) = 0 THEN 'No Data'
        WHEN COUNT(*) BETWEEN 1 AND 100 THEN 'Small Set'
        WHEN COUNT(*) BETWEEN 101 AND 1000 THEN 'Medium Set'
        WHEN COUNT(*) > 1000 THEN 'Large Set'
    END as DatasetSize,
    -- String manipulation using complex expressions
    CONCAT(
        UPPER(SUBSTRING(fa.Title, 1, 1)),
        LOWER(SUBSTRING(fa.Title, 2, LENGTH(fa.Title))),
        ' - Posted by ',
        UPPER(fa.AuthorName),
        ' in ',
        CAST(fa.YearPosted AS VARCHAR(4)),
        ' (',
        fa.PrimaryLanguage,
        ')'
    ) as FormattedTitle,
    -- NULL handling and coalescing
    COALESCE(fa.CloseReason, 'Not Closed') as FinalCloseReason,
    -- Window function usage with complex logic
    LAG(fa.ComplexMetric, 1) OVER (ORDER BY fa.ComplexMetric DESC) as PreviousMetric,
    LEAD(fa.ComplexMetric, 1) OVER (ORDER BY fa.ComplexMetric DESC) as NextMetric,
    COUNT(*) OVER() as TotalRecords,
    ROW_NUMBER() OVER (PARTITION BY fa.PrimaryLanguage ORDER BY fa.ComplexMetric DESC) as RowNumByLanguage,
    -- Correlated subqueries
    (SELECT COUNT(*) FROM Posts p5 
     WHERE p5.OwnerUserId = fa.OwnerUserId 
     AND p5.PostTypeId = 1) as UserQuestionCount,
    -- Complex string operations
    REPLACE(
        REPLACE(
            REPLACE(
                UPPER(fa.Title), 
                '<', ' '
            ), 
            '>', ' '
        ), 
        '&', ' '
    ) as CleanTitle,
    -- Mathematical operations
    ROUND(fa.ComplexMetric / NULLIF(fa.Score, 0), 2) as MetricToScoreRatio,
    -- Date calculations
    DATEDIFF(DAY, fa.CreationDate, GETDATE()) as DaysSincePost,
    -- Boolean operations
    CASE 
        WHEN fa.ActivityStatus = 'Active' AND fa.VoteCount > 10 THEN 1
        WHEN fa.ActivityStatus = 'Active' AND fa.VoteCount <= 10 THEN 0
        ELSE NULL
    END as ActiveEngagedIndicator,
    -- Grouping and filtering logic
    CASE 
        WHEN fa.QualityLevel = 1 AND fa.EngagementLevel = 'Highly Engaged' THEN 'Elite Contributor'
        WHEN fa.QualityLevel = 2 AND fa.EngagementLevel = 'Highly Engaged' THEN 'Top Contributor'
        WHEN fa.QualityLevel = 3 AND fa.EngagementLevel = 'Moderately Engaged' THEN 'Regular Contributor'
        ELSE 'Standard Contributor'
    END as ContributionTier
FROM FinalAnalysis fa
WHERE fa.Score >= 0 
    AND fa.ViewCount >= 0
    AND fa.AuthorReputation IS NOT NULL
    AND fa.ComplexMetric IS NOT NULL
    AND fa.PostCategory IS NOT NULL
ORDER BY fa.ComplexMetric DESC, fa.Score DESC, fa.ViewCount DESC
OFFSET 100 ROWS
FETCH NEXT 1000 ROWS ONLY
-- Add more advanced operations for performance testing
OPTION (MAXDOP 1, RECOMPILE, OPTIMIZE FOR UNKNOWN);