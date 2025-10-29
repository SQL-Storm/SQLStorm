-- {"query": "7132.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3932} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
        STRING_AGG(DISTINCT p.Title, ', ') as QuestionTitles,
        STRING_AGG(DISTINCT p.Tags, '; ') as QuestionTags,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        NTILE(100) OVER (ORDER BY u.Reputation DESC) as RepPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        LastCommentDate,
        QuestionCount,
        AnswerCount,
        TotalQuestionScore,
        TotalAnswerScore,
        AvgQuestionScore,
        AvgAnswerScore,
        QuestionTitles,
        QuestionTags,
        PostRank,
        RepPercentile,
        CASE 
            WHEN PostCount > 0 AND QuestionCount > 0 THEN CAST(AnswerCount AS FLOAT) / PostCount
            ELSE 0 
        END as AnswerRatio,
        CASE 
            WHEN AnswerCount > 0 THEN CAST(TotalAnswerScore AS FLOAT) / AnswerCount
            ELSE 0 
        END as AvgAnswerScorePerAnswer,
        CASE 
            WHEN QuestionCount > 0 THEN CAST(TotalQuestionScore AS FLOAT) / QuestionCount
            ELSE 0 
        END as AvgQuestionScorePerQuestion,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as OverallRank,
        RANK() OVER (PARTITION BY RepPercentile ORDER BY PostCount DESC) as LocalRank
    FROM UserActivityStats
    WHERE PostCount >= 10
),
RecentActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.PostTypeId,
        p.Tags,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as AgeInDays,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Popular'
            WHEN p.Score > 50 THEN 'Moderate'
            WHEN p.Score > 0 THEN 'Low'
            WHEN p.Score <= 0 THEN 'Negative'
            ELSE 'Unknown'
        END as ScoreCategory,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostDate,
        DATEDIFF(p.CreationDate, LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate)) as TimeBetweenPosts,
        NTH_VALUE(p.Score, 3) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as ThirdHighestScore
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATEADD(MONTH, -6, CURRENT_TIMESTAMP)
      AND p.PostTypeId IN (1, 2)
),
PostPerformance AS (
    SELECT 
        ra.PostId,
        ra.Title,
        ra.Score,
        ra.CreationDate,
        ra.OwnerUserId,
        ra.OwnerName,
        ra.PostTypeId,
        ra.Tags,
        ra.ViewCount,
        ra.CommentCount,
        ra.AnswerCount,
        ra.AgeInDays,
        ra.PostTypeCategory,
        ra.ScoreCategory,
        ra.PreviousScore,
        ra.PreviousPostDate,
        ra.TimeBetweenPosts,
        ra.ThirdHighestScore,
        CASE 
            WHEN ra.Score > (SELECT AVG(Score) FROM RecentActivity) AND ra.ViewCount > 100 THEN 'High Impact'
            WHEN ra.Score > (SELECT AVG(Score) FROM RecentActivity) THEN 'Good'
            WHEN ra.ViewCount > 100 THEN 'Visible'
            ELSE 'Standard'
        END as PerformanceCategory,
        ABS(CAST(ra.Score AS FLOAT) - (SELECT AVG(Score) FROM RecentActivity)) / (SELECT STDDEV(Score) FROM RecentActivity) as ZScore,
        CASE 
            WHEN ra.AnswerCount > 10 OR ra.CommentCount > 20 THEN 'Active'
            WHEN ra.AnswerCount > 0 OR ra.CommentCount > 5 THEN 'Engaged'
            ELSE 'Inactive'
        END as EngagementLevel,
        COALESCE(ra.Tags, '') as TagsCleaned,
        TRIM(BOTH '<>' FROM COALESCE(ra.Tags, '')) as TagsTrimmed,
        COUNT(*) OVER (PARTITION BY ra.OwnerUserId) as UserPostCount,
        ROW_NUMBER() OVER (PARTITION BY ra.OwnerUserId ORDER BY ra.Score DESC) as UserPostRank,
        RANK() OVER (ORDER BY ra.Score DESC, ra.ViewCount DESC) as GlobalPostRank
    FROM RecentActivity ra
),
ComplexCalculations AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.Score,
        pp.CreationDate,
        pp.OwnerUserId,
        pp.OwnerName,
        pp.PostTypeId,
        pp.Tags,
        pp.ViewCount,
        pp.CommentCount,
        pp.AnswerCount,
        pp.AgeInDays,
        pp.PostTypeCategory,
        pp.ScoreCategory,
        pp.PreviousScore,
        pp.PreviousPostDate,
        pp.TimeBetweenPosts,
        pp.ThirdHighestScore,
        pp.PerformanceCategory,
        pp.ZScore,
        pp.EngagementLevel,
        pp.TagsCleaned,
        pp.TagsTrimmed,
        pp.UserPostCount,
        pp.UserPostRank,
        pp.GlobalPostRank,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = pp.OwnerUserId AND p2.CreationDate >= DATEADD(DAY, -30, CURRENT_TIMESTAMP)) as PostsLast30Days,
        (SELECT AVG(Score) FROM Posts p3 WHERE p3.OwnerUserId = pp.OwnerUserId AND p3.CreationDate >= DATEADD(DAY, -30, CURRENT_TIMESTAMP)) as AvgScoreLast30Days,
        IIF(pp.PostTypeCategory LIKE '%Question%', 
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pp.PostId AND c.UserId = pp.OwnerUserId), 
            NULL) as SelfComments,
        CASE 
            WHEN pp.Score > 100 THEN 'Very High'
            WHEN pp.Score > 50 THEN 'High'
            WHEN pp.Score > 10 THEN 'Medium'
            WHEN pp.Score > 0 THEN 'Low'
            ELSE 'No Score'
        END as ScoreTier,
        CASE 
            WHEN pp.AgeInDays < 7 THEN 'New'
            WHEN pp.AgeInDays < 30 THEN 'Recent'
            WHEN pp.AgeInDays < 90 THEN 'Medium Age'
            ELSE 'Old'
        END as AgeCategory,
        CASE 
            WHEN pp.ViewCount > 1000 THEN 'Viral'
            WHEN pp.ViewCount > 500 THEN 'Popular'
            WHEN pp.ViewCount > 100 THEN 'Noticeable'
            WHEN pp.ViewCount > 10 THEN 'Seen'
            ELSE 'Obscure'
        END as VisibilityCategory,
        (SELECT COUNT(*) FROM Posts p4 WHERE p4.ParentId = pp.PostId) as ChildPostCount,
        COALESCE(
            (SELECT p5.Body FROM Posts p5 WHERE p5.Id = pp.PostId AND p5.PostTypeId = 1),
            (SELECT p6.Body FROM Posts p6 WHERE p6.Id = pp.PostId AND p6.PostTypeId = 2),
            'No Content'
        ) as PostContent,
        CASE 
            WHEN pp.ZScore > 2 THEN 'Extreme Positive'
            WHEN pp.ZScore > 1 THEN 'High Positive'
            WHEN pp.ZScore > 0 THEN 'Above Average'
            WHEN pp.ZScore = 0 THEN 'Average'
            WHEN pp.ZScore > -1 THEN 'Below Average'
            WHEN pp.ZScore > -2 THEN 'High Negative'
            ELSE 'Extreme Negative'
        END as ScoreZCategory,
        ROW_NUMBER() OVER (ORDER BY pp.ZScore DESC) as ScoreZRank,
        CASE 
            WHEN pp.SelfComments > 0 THEN 'Self Reply'
            ELSE 'No Self Reply'
        END as SelfReplier,
        IIF(pp.AnswerCount = 0, 'Unanswered', 'Answered') as AnswerStatus,
        IIF(pp.CommentCount > 0, 'Commented', 'No Comments') as CommentStatus
    FROM PostPerformance pp
),
FinalAggregation AS (
    SELECT 
        TOP 1000 
        cc.PostId,
        cc.Title,
        cc.Score,
        cc.CreationDate,
        cc.OwnerUserId,
        cc.OwnerName,
        cc.PostTypeId,
        cc.Tags,
        cc.ViewCount,
        cc.CommentCount,
        cc.AnswerCount,
        cc.AgeInDays,
        cc.PostTypeCategory,
        cc.ScoreCategory,
        cc.PreviousScore,
        cc.PreviousPostDate,
        cc.TimeBetweenPosts,
        cc.ThirdHighestScore,
        cc.PerformanceCategory,
        cc.ZScore,
        cc.EngagementLevel,
        cc.TagsCleaned,
        cc.TagsTrimmed,
        cc.UserPostCount,
        cc.UserPostRank,
        cc.GlobalPostRank,
        cc.PostsLast30Days,
        cc.AvgScoreLast30Days,
        cc.SelfComments,
        cc.ScoreTier,
        cc.AgeCategory,
        cc.VisibilityCategory,
        cc.ChildPostCount,
        cc.PostContent,
        cc.ScoreZCategory,
        cc.ScoreZRank,
        cc.SelfReplier,
        cc.AnswerStatus,
        cc.CommentStatus,
        (
            SELECT STRING_AGG(
                CONCAT('Badge: ', b.Name, ' (', b.Date, ')'),
                '; '
            ) 
            FROM Badges b 
            WHERE b.UserId = cc.OwnerUserId 
            AND b.Date >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)
        ) as RecentBadges,
        (
            SELECT COUNT(*) 
            FROM Posts p7 
            WHERE p7.OwnerUserId = cc.OwnerUserId 
            AND p7.CreationDate > DATEADD(DAY, -7, CURRENT_TIMESTAMP)
        ) as PostsLastWeek,
        (
            SELECT AVG(Score) 
            FROM Posts p8 
            WHERE p8.OwnerUserId = cc.OwnerUserId 
            AND p8.PostTypeId = 1
            AND p8.CreationDate > DATEADD(MONTH, -3, CURRENT_TIMESTAMP)
        ) as AvgQuestionScore3Months,
        COALESCE(
            (SELECT AVG(Score) FROM Posts p9 WHERE p9.OwnerUserId = cc.OwnerUserId),
            0
        ) as OverallAvgScore,
        CASE 
            WHEN cc.PostContent IS NOT NULL 
            AND LEN(cc.PostContent) > 1000 THEN 'Very Long'
            WHEN cc.PostContent IS NOT NULL 
            AND LEN(cc.PostContent) > 500 THEN 'Long'
            WHEN cc.PostContent IS NOT NULL 
            AND LEN(cc.PostContent) > 100 THEN 'Medium'
            WHEN cc.PostContent IS NOT NULL THEN 'Short'
            ELSE 'No Content'
        END as ContentLength,
        IIF(
            cc.Score > (SELECT AVG(Score) FROM ComplexCalculations) 
            AND cc.ViewCount > (SELECT AVG(ViewCount) FROM ComplexCalculations),
            'High Performer',
            'Regular'
        ) as PerformanceLabel,
        IIF(
            cc.CommentCount > 20 AND cc.AnswerCount >= 5,
            'High Engagement',
            'Standard Engagement'
        ) as EngagementLabel,
        CASE 
            WHEN cc.AgeInDays <= 7 THEN 'Fresh'
            WHEN cc.AgeInDays BETWEEN 8 AND 30 THEN 'Stable'
            WHEN cc.AgeInDays > 30 THEN 'Legacy'
            ELSE 'Unknown'
        END as AgeLabel,
        NULLIF(
            DATEDIFF(
                DAY,
                cc.CreationDate,
                (SELECT MAX(CreationDate) FROM Posts WHERE OwnerUserId = cc.OwnerUserId)
            ),
            0
        ) as DaysSinceLastPost,
        (SELECT MAX(Reputation) FROM Users WHERE Id = cc.OwnerUserId) as CurrentReputation,
        ISNULL(
            (SELECT TOP 1 Name FROM PostTypes WHERE Id = cc.PostTypeId), 
            'Unknown'
        ) as PostTypeName,
        CAST(COUNT(*) OVER() AS VARCHAR(10)) as TotalPostsProcessed,
        ROW_NUMBER() OVER(ORDER BY cc.Score DESC, cc.ViewCount DESC) as FinalRank
    FROM ComplexCalculations cc
    WHERE cc.OwnerUserId IS NOT NULL
)
SELECT 
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.CreationDate,
    fa.OwnerUserId,
    fa.OwnerName,
    fa.PostTypeId,
    fa.Tags,
    fa.ViewCount,
    fa.CommentCount,
    fa.AnswerCount,
    fa.AgeInDays,
    fa.PostTypeCategory,
    fa.ScoreCategory,
    fa.PreviousScore,
    fa.PreviousPostDate,
    fa.TimeBetweenPosts,
    fa.ThirdHighestScore,
    fa.PerformanceCategory,
    fa.ZScore,
    fa.EngagementLevel,
    fa.TagsCleaned,
    fa.TagsTrimmed,
    fa.UserPostCount,
    fa.UserPostRank,
    fa.GlobalPostRank,
    fa.PostsLast30Days,
    fa.AvgScoreLast30Days,
    fa.SelfComments,
    fa.ScoreTier,
    fa.AgeCategory,
    fa.VisibilityCategory,
    fa.ChildPostCount,
    LEFT(fa.PostContent, 200) + '...' as PostContentPreview,
    fa.ScoreZCategory,
    fa.ScoreZRank,
    fa.SelfReplier,
    fa.AnswerStatus,
    fa.CommentStatus,
    fa.RecentBadges,
    fa.PostsLastWeek,
    fa.AvgQuestionScore3Months,
    fa.OverallAvgScore,
    fa.ContentLength,
    fa.PerformanceLabel,
    fa.EngagementLabel,
    fa.AgeLabel,
    fa.DaysSinceLastPost,
    fa.CurrentReputation,
    fa.PostTypeName,
    fa.TotalPostsProcessed,
    fa.FinalRank,
    (
        SELECT COUNT(*) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = fa.OwnerUserId 
        AND p10.Score > fa.Score
    ) as AboveScoreCount,
    (
        SELECT AVG(Score) 
        FROM Posts p11 
        WHERE p11.OwnerUserId = fa.OwnerUserId 
        AND p11.PostTypeId = 1 
        AND p11.Score IS NOT NULL
    ) as AvgScoreOfSameUserQuestions,
    (SELECT COUNT(DISTINCT PostId) FROM Comments WHERE UserId = fa.OwnerUserId) as CommentCountByUser,
    IIF(fa.PostTypeName = 'Question', 1, 0) as IsQuestion,
    IIF(fa.PostTypeName = 'Answer', 1, 0) as IsAnswer,
    CASE 
        WHEN fa.Score > 50 THEN 
            (SELECT COUNT(*) FROM FinalAggregation WHERE Score > 50)
        ELSE 0 
    END as HighScoreCount,
    ABS(fa.Score) as AbsoluteScore,
    CASE WHEN fa.ViewCount > 100 THEN 1 ELSE 0 END as IsViewed,
    CASE WHEN fa.CommentCount > 5 THEN 1 ELSE 0 END as HasComments,
    CASE WHEN fa.AnswerCount > 0 THEN 1 ELSE 0 END as HasAnswers,
    IIF(fa.Score > (SELECT AVG(Score) FROM FinalAggregation), 1, 0) as AboveAverageScore,
    ROUND(
        CAST(fa.ViewCount AS FLOAT) / NULLIF(fa.Score, 0), 
        2
    ) as ViewScoreRatio,
    IIF(
        fa.PostsLast30Days > 0 
        AND fa.AvgScoreLast30Days > 0,
        CAST(fa.AvgScoreLast30Days AS FLOAT),
        NULL
    ) as AvgScore,
    CASE 
        WHEN fa.ZScore > 2 THEN 
            'Extreme Performance'
        WHEN fa.ZScore > 1 THEN 
            'Above Average'
        WHEN fa.ZScore >= 0 THEN 
            'Average'
        WHEN fa.ZScore > -1 THEN 
            'Below Average'
        WHEN fa.ZScore > -2 THEN 
            'Below Average'
        ELSE 
            'Poor Performance'
    END as PerformanceGrade,
    IIF(
        fa.GlobalPostRank IS NOT NULL 
        AND fa.GlobalPostRank <= 10,
        'Top Performer',
        'Regular'
    ) as RankingLabel
FROM FinalAggregation fa
WHERE fa.PostId IS NOT NULL
ORDER BY fa.Score DESC, fa.ViewCount DESC, fa.CreationDate DESC