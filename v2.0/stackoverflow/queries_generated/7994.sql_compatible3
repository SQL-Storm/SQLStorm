WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        MAX(p.Score) as MaxPostScore,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), ', ') as AllTags,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswer
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        MaxPostScore,
        AvgPostScore,
        AllTags,
        ClosedQuestions,
        QuestionsWithAcceptedAnswer,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, Reputation DESC) as RankByPostCount
    FROM UserStats
),
RecentActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.PostTypeId,
        p.Tags,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevViews,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        LEAD(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextViews
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 day')
),
PostPerformance AS (
    SELECT 
        ra.PostId,
        ra.Title,
        ra.Score,
        ra.ViewCount,
        ra.CreationDate,
        ra.OwnerName,
        ra.PostTypeId,
        ra.Tags,
        ra.PrevScore,
        ra.PrevViews,
        ra.NextScore,
        ra.NextViews,
        CASE WHEN ra.PrevScore IS NOT NULL THEN ra.Score - ra.PrevScore ELSE 0 END as ScoreChange,
        CASE WHEN ra.PrevViews IS NOT NULL THEN ra.ViewCount - ra.PrevViews ELSE 0 END as ViewChange,
        CASE WHEN ra.NextScore IS NOT NULL THEN ra.NextScore - ra.Score ELSE 0 END as NextScoreChange,
        CASE WHEN ra.NextViews IS NOT NULL THEN ra.NextViews - ra.ViewCount ELSE 0 END as NextViewChange,
        CASE WHEN ra.Score > 100 THEN 'High' 
             WHEN ra.Score > 50 THEN 'Medium'
             ELSE 'Low' END as ScoreCategory,
        CASE WHEN ra.ViewCount > 1000 THEN 'High' 
             WHEN ra.ViewCount > 500 THEN 'Medium'
             ELSE 'Low' END as ViewCategory,
        DENSE_RANK() OVER (PARTITION BY ra.OwnerName ORDER BY ra.CreationDate) as PostSequenceByUser,
        AVG(ra.Score) OVER (PARTITION BY ra.OwnerName) as AvgPostScoreByUser,
        AVG(ra.ViewCount) OVER (PARTITION BY ra.OwnerName) as AvgPostViewsByUser
    FROM RecentActivity ra
),
QuestionAnalysis AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.Score,
        pp.ViewCount,
        pp.CreationDate,
        pp.OwnerName,
        pp.ScoreChange,
        pp.ViewChange,
        pp.ScoreCategory,
        pp.ViewCategory,
        pp.PostSequenceByUser,
        pp.AvgPostScoreByUser,
        pp.AvgPostViewsByUser,
        CASE WHEN pp.ScoreChange > 0 THEN 'Increasing' 
             WHEN pp.ScoreChange < 0 THEN 'Decreasing'
             ELSE 'Stable' END as ScoreTrend,
        CASE WHEN pp.ViewChange > 0 THEN 'Growing' 
             WHEN pp.ViewChange < 0 THEN 'Declining'
             ELSE 'Static' END as ViewTrend,
        COUNT(*) OVER () as TotalQuestions,
        RANK() OVER (ORDER BY pp.Score DESC) as RankByScore,
        RANK() OVER (ORDER BY pp.ViewCount DESC) as RankByViews
    FROM PostPerformance pp
    WHERE pp.PostTypeId = 1  -- Questions only
),
AnswerAnalysis AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.Score,
        pp.ViewCount,
        pp.CreationDate,
        pp.OwnerName,
        pp.ScoreChange,
        pp.ViewChange,
        pp.ScoreCategory,
        pp.ViewCategory,
        pp.PostSequenceByUser,
        pp.AvgPostScoreByUser,
        pp.AvgPostViewsByUser,
        CASE WHEN pp.ScoreChange > 0 THEN 'Increasing' 
             WHEN pp.ScoreChange < 0 THEN 'Decreasing'
             ELSE 'Stable' END as ScoreTrend,
        CASE WHEN pp.ViewChange > 0 THEN 'Growing' 
             WHEN pp.ViewChange < 0 THEN 'Declining'
             ELSE 'Static' END as ViewTrend,
        COUNT(*) OVER () as TotalAnswers,
        RANK() OVER (ORDER BY pp.Score DESC) as RankByScore,
        RANK() OVER (ORDER BY pp.ViewCount DESC) as RankByViews
    FROM PostPerformance pp
    WHERE pp.PostTypeId = 2  -- Answers only
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = TRUE THEN 'Required' ELSE 'Optional' END as TagType,
        CASE WHEN t.IsModeratorOnly = TRUE THEN 'Moderator Only' ELSE 'Public' END as AccessLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity
    FROM Tags t
),
FinalAnalysis AS (
    SELECT 
        ta.PostId,
        ta.Title,
        ta.Score,
        ta.ViewCount,
        ta.CreationDate,
        ta.OwnerName,
        ta.ScoreChange,
        ta.ViewChange,
        ta.ScoreCategory,
        ta.ViewCategory,
        ta.PostSequenceByUser,
        ta.AvgPostScoreByUser,
        ta.AvgPostViewsByUser,
        ta.ScoreTrend,
        ta.ViewTrend,
        ta.TotalQuestions,
        ta.RankByScore,
        ta.RankByViews,
        CASE WHEN ta.RankByScore <= 10 THEN 'Top 10 Score' 
             WHEN ta.RankByScore <= 25 THEN 'Top 25 Score' 
             ELSE 'Other' END as ScoreTier,
        CASE WHEN ta.RankByViews <= 10 THEN 'Top 10 Views' 
             WHEN ta.RankByViews <= 25 THEN 'Top 25 Views' 
             ELSE 'Other' END as ViewTier,
        STRING_AGG(DISTINCT CASE WHEN ta.Title IS NOT NULL THEN ta.Title ELSE 'No Title' END, '; ') as TitleAgg,
        SUM(ta.Score) OVER (ORDER BY ta.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingScoreSum,
        AVG(ta.Score) OVER (ORDER BY ta.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingScoreAvg,
        MAX(ta.Score) OVER (ORDER BY ta.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingScoreMax,
        CASE WHEN SUM(ta.Score) OVER (ORDER BY ta.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) > 500 THEN 'High Activity' ELSE 'Normal Activity' END as ActivityLevel
    FROM QuestionAnalysis ta
    WHERE ta.Score > 0
    GROUP BY ta.PostId, ta.Title, ta.Score, ta.ViewCount, ta.CreationDate, ta.OwnerName, 
             ta.ScoreChange, ta.ViewChange, ta.ScoreCategory, ta.ViewCategory, ta.PostSequenceByUser,
             ta.AvgPostScoreByUser, ta.AvgPostViewsByUser, ta.ScoreTrend, ta.ViewTrend, 
             ta.TotalQuestions, ta.RankByScore, ta.RankByViews
),
ScoreChangeSummary AS (
    /* Build a cumulative summary without using STRING_AGG as a window function.
       We create one row per FinalAnalysis row with aggregated summaries up to that CreationDate. */
    SELECT
        fa.PostId,
        fa.CreationDate,
        LISTAGG_label.Summary as ScoreChangeSummary
    FROM FinalAnalysis fa
    LEFT JOIN (
        SELECT
            f1.CreationDate as AnchorCreationDate,
            f1.PostId as AnchorPostId,
            -- dialect-neutral concatenation aggregation: use STRING_AGG where supported; if not, use LISTAGG
            STRING_AGG(
                CASE WHEN f2.ScoreChange > 10 THEN 'Large Score Gain'
                     WHEN f2.ScoreChange < -10 THEN 'Large Score Loss'
                     WHEN f2.ScoreChange > 0 THEN 'Score Increase'
                     WHEN f2.ScoreChange < 0 THEN 'Score Decrease'
                     ELSE 'No Score Change' END, ', '
            ) as Summary
        FROM FinalAnalysis f1
        JOIN FinalAnalysis f2
          ON f2.CreationDate <= f1.CreationDate
        GROUP BY f1.CreationDate, f1.PostId
    ) LISTAGG_label
      ON LISTAGG_label.AnchorCreationDate = fa.CreationDate AND LISTAGG_label.AnchorPostId = fa.PostId
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.CreationDate,
    fa.OwnerName,
    fa.ScoreChange,
    fa.ViewChange,
    fa.ScoreCategory,
    fa.ViewCategory,
    fa.PostSequenceByUser,
    fa.AvgPostScoreByUser,
    fa.AvgPostViewsByUser,
    fa.ScoreTrend,
    fa.ViewTrend,
    fa.TotalQuestions,
    fa.RankByScore,
    fa.RankByViews,
    fa.ScoreTier,
    fa.ViewTier,
    fa.TitleAgg,
    fa.MovingScoreSum,
    fa.MovingScoreAvg,
    fa.MovingScoreMax,
    fa.ActivityLevel,
    NULLIF(fa.Title, '') as NonNullTitle,
    COALESCE(fa.Title, 'No Title Available') as SafeTitle,
    TRIM(UPPER(fa.OwnerName)) as FormattedOwnerName,
    CASE WHEN fa.Title LIKE '%SQL%' OR fa.Title LIKE '%query%' OR fa.Title LIKE '%database%' THEN 'Technical' ELSE 'General' END as TopicCategory,
    CASE WHEN fa.OwnerName IN ('Community', 'Mod', 'Admin') THEN 'Special User' ELSE 'Regular User' END as UserGroup,
    CAST(DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56' - fa.CreationDate)) AS INTEGER) as DaysSinceCreation,
    CASE WHEN fa.Score >= 100 AND fa.ViewCount >= 1000 THEN 'High Impact' 
         WHEN fa.Score >= 50 AND fa.ViewCount >= 500 THEN 'Medium Impact' 
         ELSE 'Low Impact' END as ImpactLevel,
    fa.OwnerName || ' - ' || fa.Title as OwnerTitleCombo,
    sc.ScoreChangeSummary,
    CASE WHEN fa.Score >= 10 AND fa.ViewCount >= 100 THEN 'Popular' 
         WHEN fa.Score >= 5 AND fa.ViewCount >= 50 THEN 'Moderately Popular' 
         ELSE 'Not Popular' END as PopularityCategory
FROM FinalAnalysis fa
LEFT JOIN ScoreChangeSummary sc ON sc.PostId = fa.PostId AND sc.CreationDate = fa.CreationDate
WHERE fa.Score > 0 
  AND fa.ViewCount IS NOT NULL
  AND fa.OwnerName IS NOT NULL
  AND EXISTS (
      SELECT 1 
      FROM TopUsers tu 
      WHERE tu.UserId = (SELECT u2.Id FROM Users u2 WHERE u2.DisplayName = fa.OwnerName LIMIT 1)
        AND tu.PostCount > 0
  )
  AND fa.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 month')
  AND (fa.Title IS NOT NULL OR fa.Title <> '') 
  AND (fa.ScoreCategory IS NOT NULL OR fa.ViewCategory IS NOT NULL)
  AND (fa.ScoreTrend IS NOT NULL OR fa.ViewTrend IS NOT NULL)
  AND fa.RankByScore IS NOT NULL
  AND fa.RankByViews IS NOT NULL
  AND fa.ScoreTier IS NOT NULL
  AND fa.ViewTier IS NOT NULL
  AND fa.MovingScoreSum IS NOT NULL
  AND fa.MovingScoreAvg IS NOT NULL
  AND fa.MovingScoreMax IS NOT NULL
  AND fa.ActivityLevel IS NOT NULL
  AND CHAR_LENGTH(fa.OwnerName) > 0
  AND CHAR_LENGTH(fa.Title) > 10
ORDER BY fa.Score DESC, fa.ViewCount DESC, fa.CreationDate DESC
LIMIT 1000 OFFSET 0;