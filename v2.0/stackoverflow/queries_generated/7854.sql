-- {"query": "7854.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2169} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AvgScore,
        MAX(p.CreationDate) as LatestPostDate,
        DATEDIFF(day, MIN(p.CreationDate), MAX(p.CreationDate)) as ActiveDays,
        COUNT(DISTINCT CASE WHEN p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
        COUNT(DISTINCT CASE WHEN p.CommentCount > 0 THEN p.Id END) as PostsWithComments,
        STRING_AGG(DISTINCT LEFT(p.Title, 50), '; ') as SampleTitles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        TotalScore,
        AvgScore,
        LatestPostDate,
        ActiveDays,
        QuestionsWithAnswers,
        PostsWithComments,
        SampleTitles,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RankByReputation
    FROM UserPostStats
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(*) as TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) as BronzeBadges,
        STRING_AGG(Name, ', ') as BadgeNames
    FROM Badges
    WHERE Date >= '2015-01-01'
    GROUP BY UserId
),
QuestionAnalysis AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        COALESCE(p.Tags, '') as Tags,
        CASE 
            WHEN p.AnswerCount = 0 THEN 'No Answers'
            WHEN p.AnswerCount = 1 THEN 'One Answer'
            WHEN p.AnswerCount BETWEEN 2 AND 5 THEN 'Few Answers'
            WHEN p.AnswerCount BETWEEN 6 AND 10 THEN 'Many Answers'
            ELSE 'Very Many Answers'
        END as AnswerCategory,
        CASE 
            WHEN p.Score > 100 THEN 'Very High'
            WHEN p.Score > 50 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysSinceLastActivity,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2020-01-01'
    AND p.ViewCount >= 100
),
AnswerAnalysis AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName as OwnerName,
        DATEDIFF(day, q.CreationDate, a.CreationDate) as DaysToAnswer,
        CASE 
            WHEN a.Score > 10 THEN 'High Quality'
            WHEN a.Score > 0 THEN 'Moderate Quality'
            ELSE 'Low Quality'
        END as QualityCategory,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as AnswerRank
    FROM Posts a
    LEFT JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
    AND q.PostTypeId = 1
    AND q.CreationDate >= '2020-01-01'
),
CombinedAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.TotalScore,
        tu.AvgScore,
        tu.LatestPostDate,
        tu.ActiveDays,
        tu.QuestionsWithAnswers,
        tu.PostsWithComments,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        CASE 
            WHEN ub.TotalBadges > 10 THEN 'Badge Collector'
            WHEN ub.TotalBadges > 5 THEN 'Active Contributor'
            ELSE 'Occasional Participant'
        END as BadgeStatus,
        qa.QuestionId,
        qa.Title as QuestionTitle,
        qa.Score as QuestionScore,
        qa.ViewCount,
        qa.AnswerCount,
        qa.CommentCount,
        qa.FavoriteCount,
        qa.AnswerCategory,
        qa.ScoreCategory,
        qa.DaysSinceLastActivity,
        aa.AnswerId,
        aa.Score as AnswerScore,
        aa.DaysToAnswer,
        aa.QualityCategory,
        CASE 
            WHEN aa.AnswerRank = 1 THEN 'Top Answer'
            WHEN aa.AnswerRank <= 5 THEN 'Good Answer'
            ELSE 'Average Answer'
        END as AnswerQuality,
        DATEDIFF(month, tu.LatestPostDate, CURRENT_TIMESTAMP) as MonthsSinceLastPost,
        CASE 
            WHEN tu.Reputation > 10000 THEN 'Elite'
            WHEN tu.Reputation > 5000 THEN 'Experienced'
            WHEN tu.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ExpertiseLevel
    FROM TopUsers tu
    LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
    LEFT JOIN QuestionAnalysis qa ON tu.UserId = qa.OwnerUserId
    LEFT JOIN AnswerAnalysis aa ON qa.QuestionId = aa.QuestionId
    WHERE tu.RankByScore <= 100 OR ub.TotalBadges >= 5
),
FinalAnalysis AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        TotalScore,
        AvgScore,
        LatestPostDate,
        ActiveDays,
        QuestionsWithAnswers,
        PostsWithComments,
        TotalBadges,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        BadgeStatus,
        QuestionId,
        QuestionTitle,
        QuestionScore,
        ViewCount,
        AnswerCount,
        CommentCount,
        FavoriteCount,
        AnswerCategory,
        ScoreCategory,
        DaysSinceLastActivity,
        AnswerId,
        AnswerScore,
        DaysToAnswer,
        QualityCategory,
        AnswerQuality,
        MonthsSinceLastPost,
        ExpertiseLevel,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY QuestionScore DESC, AnswerScore DESC) as PostSequence,
        CASE 
            WHEN AVG(TotalScore) OVER (PARTITION BY UserId) > AVG(TotalScore) OVER () THEN 'Above Average'
            WHEN AVG(TotalScore) OVER (PARTITION BY UserId) < AVG(TotalScore) OVER () THEN 'Below Average'
            ELSE 'Average'
        END as PerformanceLevel,
        CONCAT(
            DisplayName, 
            ' (', 
            CASE WHEN GoldBadges > 0 THEN CAST(GoldBadges AS VARCHAR) + 'G' ELSE '' END,
            CASE WHEN SilverBadges > 0 THEN CAST(SilverBadges AS VARCHAR) + 'S' ELSE '' END,
            CASE WHEN BronzeBadges > 0 THEN CAST(BronzeBadges AS VARCHAR) + 'B' ELSE '' END,
            ')'
        ) as UserDisplay,
        CASE 
            WHEN QuestionScore > 0 AND AnswerScore > 0 THEN 'Active Contributor'
            WHEN QuestionScore > 0 THEN 'Questioner'
            WHEN AnswerScore > 0 THEN 'Answerer'
            ELSE 'Inactive'
        END as ParticipationType,
        IIF(AnswerCount > 0, 
            CAST(AnswerCount AS FLOAT) / NULLIF(QuestionCount, 0), 
            NULL) as AnswerRatio
    FROM CombinedAnalysis
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    Questions,
    Answers,
    TotalScore,
    AvgScore,
    LatestPostDate,
    ActiveDays,
    QuestionsWithAnswers,
    PostsWithComments,
    TotalBadges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    BadgeStatus,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    AnswerCategory,
    ScoreCategory,
    DaysSinceLastActivity,
    AnswerId,
    AnswerScore,
    DaysToAnswer,
    QualityCategory,
    AnswerQuality,
    MonthsSinceLastPost,
    ExpertiseLevel,
    PostSequence,
    PerformanceLevel,
    UserDisplay,
    ParticipationType,
    AnswerRatio,
    CASE 
        WHEN TotalScore > 500 AND TotalBadges > 10 THEN 'High Performer'
        WHEN TotalScore > 250 AND ActiveDays > 365 THEN 'Consistent Contributor'
        WHEN TotalScore > 100 AND AnswerCount > 10 THEN 'Quality Contributor'
        ELSE 'Regular Member'
    END as CommunityRole
FROM FinalAnalysis
WHERE 
    (QuestionId IS NOT NULL OR AnswerId IS NOT NULL)
    AND (Reputation > 100 OR TotalBadges > 0)
ORDER BY 
    TotalScore DESC,
    Reputation DESC,
    LatestPostDate DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;