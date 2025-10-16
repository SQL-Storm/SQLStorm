WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN u.Reputation < 100 THEN 'Novice'
            WHEN u.Reputation BETWEEN 100 AND 999 THEN 'Contributor'
            WHEN u.Reputation BETWEEN 1000 AND 9999 THEN 'Expert'
            ELSE 'Master'
        END AS ReputationTier,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        COALESCE(STDDEV_POP(CAST(p.Score AS NUMERIC)), 0) AS ScoreStdDev
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
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p1.ViewCount, 0) AS ExcerptViews,
        COALESCE(p2.ViewCount, 0) AS WikiViews,
        CASE 
            WHEN t.Count > 100 THEN 'Highly Popular'
            WHEN t.Count > 50 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Niche'
        END AS TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS RankByPopularity
    FROM Tags t
    LEFT JOIN Posts p1 ON t.ExcerptPostId = p1.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
    WHERE t.TagName IS NOT NULL
),
QuestionAnalysis AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Tags,
        CASE 
            WHEN p.AnswerCount = 0 THEN 'No Answers'
            WHEN p.AnswerCount = 1 THEN 'One Answer'
            WHEN p.AnswerCount <= 5 THEN 'Few Answers'
            ELSE 'Many Answers'
        END AS AnswerDensity,
        (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate) AS DaysSinceCreation,
        p.Score - LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS ScoreChange,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS UserAvgScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserQuestionSequence,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 25 THEN 'Well Voted'
            WHEN p.Score > 0 THEN 'Neutral'
            ELSE 'Lowly Voted'
        END AS VoteStatus,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 100 THEN 'Popular'
            WHEN p.ViewCount > 10 THEN 'Moderate'
            ELSE 'Low'
        END AS ViewStatus
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerDistribution AS (
    SELECT 
        a.ParentId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswers,
        SUM(CASE WHEN a.Score < 0 THEN 1 ELSE 0 END) AS NegativeAnswers,
        SUM(CASE WHEN a.Score = 0 THEN 1 ELSE 0 END) AS NeutralAnswers,
        (SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS PositiveRatio,
        STRING_AGG(CASE WHEN a.Score > 0 THEN a.OwnerDisplayName ELSE NULL END, ', ') AS TopScoringAuthors
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
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        q.AnswerCount,
        q.AnswerDensity,
        q.VoteStatus,
        q.ViewStatus,
        ad.AnswerCount AS RelatedAnswerCount,
        ad.AvgAnswerScore,
        ad.PositiveRatio,
        CASE 
            WHEN q.Score > 0 AND q.ViewCount > 100 THEN 1
            WHEN q.Score <= 0 AND q.ViewCount <= 10 THEN 0
            ELSE -1
        END AS QualityClassification,
        CASE 
            WHEN u.Views IS NOT NULL THEN 'Active User'
            WHEN u.Views IS NULL THEN 'Inactive User'
            ELSE 'Unknown'
        END AS ActivityStatus,
        CASE 
            WHEN q.DaysSinceCreation <= INTERVAL '30 days' THEN 'New'
            WHEN q.DaysSinceCreation <= INTERVAL '90 days' THEN 'Recent'
            ELSE 'Old'
        END AS QuestionAge,
        DENSE_RANK() OVER (ORDER BY q.Score DESC) AS ScoreRank,
        NTILE(4) OVER (ORDER BY q.ViewCount DESC) AS ViewQuartile,
        PERCENT_RANK() OVER (ORDER BY ua.TotalScore DESC) AS ScorePercentile,
        LAG(q.Score) OVER (ORDER BY q.CreationDate) AS PrevQuestionScore,
        LEAD(q.Score) OVER (ORDER BY q.CreationDate) AS NextQuestionScore,
        COALESCE(
            CASE 
                WHEN q.Score > (SELECT AVG(CAST(Score AS NUMERIC)) FROM Posts WHERE PostTypeId = 1) THEN 1
                ELSE 0
            END,
            0
        ) AS AboveAverageScore,
        COALESCE(
            CASE 
                WHEN q.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) THEN 1
                ELSE 0
            END,
            0
        ) AS AboveAverageViews,
        CASE 
            WHEN q.Tags IS NOT NULL AND LENGTH(q.Tags) > 0 THEN 
                'Tagged with: ' || SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2)
            ELSE 'No Tags'
        END AS TagInfo,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v 
             WHERE v.PostId = q.QuestionId 
             AND v.VoteTypeId IN (2, 3)), 0
        ) AS TotalVotes,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c 
             WHERE c.PostId = q.QuestionId), 0
        ) AS CommentCountOnQuestion,
        CASE 
            WHEN q.AnswerCount > 0 AND q.AnswerCount = (
                SELECT COUNT(*) 
                FROM Posts p2 
                WHERE p2.ParentId = q.QuestionId 
                AND p2.PostTypeId = 2
            ) THEN 'All Answers Present'
            ELSE 'Some Answers Missing'
        END AS AnswerCompleteness,
        CASE 
            WHEN q.OwnerUserId IN (
                SELECT DISTINCT UserId 
                FROM Badges 
                WHERE Name IN ('Populist', 'Great Question', 'Good Question')
            ) THEN 'Awarded Question'
            ELSE 'Regular Question'
        END AS QuestionAwardStatus,
        COALESCE(q.Score - q.UserAvgScore, 0) AS ScoreVsUserAvg,
        ABS(q.AnswerCount - COALESCE(ad.AnswerCount, 0)) AS AnswerCountDelta,
        TRIM(BOTH '<>' FROM q.Tags) AS CleanedTags
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
    END AS UserPerformanceCategory
FROM ComplexQueryResults
WHERE TagCount > 10
AND QuestionScore > -10
AND QuestionViews > 0
AND PostCount >= 5
ORDER BY ScoreRank, ViewQuartile, AnswerCountDelta ASC
LIMIT 20000;