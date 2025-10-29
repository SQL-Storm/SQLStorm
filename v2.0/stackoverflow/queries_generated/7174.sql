-- {"query": "7174.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3107} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LatestPostDate,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags END, ';') AS AllQuestionTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        TotalQuestionScore,
        TotalAnswerScore,
        LatestPostDate,
        AvgAnswerScore,
        AllQuestionTags,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC, AnswerCount DESC) AS RankByScore,
        RANK() OVER (ORDER BY Reputation DESC) AS RankByReputation,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) AS RankByPostCount
    FROM UserPostStats
    WHERE TotalPosts > 0
),
TopBadges AS (
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Date,
        b.Class,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            ELSE 'Bronze' 
        END AS BadgeTier,
        COUNT(*) OVER (PARTITION BY b.UserId) AS TotalBadges,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM Badges b
    WHERE b.UserId IS NOT NULL
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.Score >= 100 THEN 'High Engagement'
            WHEN p.Score >= 25 THEN 'Medium Engagement'
            WHEN p.Score >= 0 THEN 'Low Engagement'
            ELSE 'Negative Engagement'
        END AS EngagementLevel,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                CASE 
                    WHEN p.Score / NULLIF(p.AnswerCount, 0) >= 10 THEN 'High Quality Answers'
                    WHEN p.Score / NULLIF(p.AnswerCount, 0) >= 5 THEN 'Medium Quality Answers'
                    ELSE 'Low Quality Answers'
                END
            ELSE 'No Answers'
        END AS AnswerQuality,
        CASE 
            WHEN p.CommentCount > 0 THEN 
                CASE 
                    WHEN p.CommentCount > 10 THEN 'High Comment Activity'
                    WHEN p.CommentCount > 5 THEN 'Medium Comment Activity'
                    ELSE 'Low Comment Activity'
                END
            ELSE 'No Comments'
        END AS CommentActivity,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ', '), 'No Tags') AS PostTags,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(10) OVER (ORDER BY p.ViewCount DESC) AS ViewDecile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) AS NextScore,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RecencyRank,
        COUNT(*) OVER () AS TotalPostsInAnalysis
    FROM Posts p
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, p.PostTypeId, p.OwnerUserId, p.Tags
),
ComplexJoinResults AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.TotalQuestionScore,
        tu.TotalAnswerScore,
        tu.LatestPostDate,
        tu.AvgAnswerScore,
        tu.AllQuestionTags,
        tu.RankByScore,
        tu.RankByReputation,
        tu.RankByPostCount,
        tb.BadgeName,
        tb.BadgeTier,
        tb.TotalBadges,
        tb.BadgeRank,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.CreationDate,
        pa.PostTypeId,
        pa.Tags,
        pa.EngagementLevel,
        pa.AnswerQuality,
        pa.CommentActivity,
        pa.PostTags,
        pa.ScoreRank,
        pa.ViewDecile,
        pa.PreviousScore,
        pa.NextScore,
        pa.RecencyRank,
        pa.TotalPostsInAnalysis,
        CASE 
            WHEN pa.Score > tu.TotalQuestionScore / NULLIF(tu.QuestionCount, 0) THEN 'Above Average'
            WHEN pa.Score < tu.TotalQuestionScore / NULLIF(tu.QuestionCount, 0) THEN 'Below Average'
            ELSE 'Average'
        END AS RelativeScore,
        CASE 
            WHEN COALESCE(pa.Score, 0) - COALESCE(pa.PreviousScore, 0) > 0 THEN 'Improvement'
            WHEN COALESCE(pa.Score, 0) - COALESCE(pa.PreviousScore, 0) < 0 THEN 'Degradation'
            ELSE 'Stable'
        END AS ScoreTrend,
        CASE 
            WHEN (pa.ViewCount IS NOT NULL AND pa.ViewCount > 1000) OR pa.EngagementLevel IN ('High Engagement', 'Medium Engagement') THEN 'Prominent Post'
            ELSE 'Regular Post'
        END AS PostProminence,
        CASE 
            WHEN pa.Score > 50 AND pa.AnswerCount > 10 THEN 'High-Quality Question'
            WHEN pa.Score > 25 AND pa.AnswerCount > 5 THEN 'Moderate-Quality Question'
            WHEN pa.Score > 10 THEN 'Low-Quality Question'
            ELSE 'Question with Low Engagement'
        END AS QuestionQuality,
        'Post Summary: ' || pa.Title || ' (' || pa.EngagementLevel || ') - Score: ' || pa.Score || ' - Views: ' || pa.ViewCount AS PostOverview,
        CASE 
            WHEN pa.CommentCount > 0 AND pa.CommentCount <= 5 THEN 'Few Comments'
            WHEN pa.CommentCount > 5 AND pa.CommentCount <= 10 THEN 'Moderate Comments'
            WHEN pa.CommentCount > 10 THEN 'Many Comments'
            ELSE 'No Comments'
        END AS CommentIntensity,
        CASE 
            WHEN pa.PostTypeId = 1 THEN 'Question'
            WHEN pa.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other Post Type'
        END AS PostTypeDescription
    FROM TopUsers tu
    LEFT JOIN TopBadges tb ON tu.UserId = tb.UserId
    LEFT JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
    WHERE tu.UserId > 0
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    QuestionCount,
    AnswerCount,
    TotalQuestionScore,
    TotalAnswerScore,
    LatestPostDate,
    AvgAnswerScore,
    AllQuestionTags,
    RankByScore,
    RankByReputation,
    RankByPostCount,
    BadgeName,
    BadgeTier,
    TotalBadges,
    BadgeRank,
    PostId,
    Title,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    CreationDate,
    PostTypeId,
    Tags,
    EngagementLevel,
    AnswerQuality,
    CommentActivity,
    PostTags,
    ScoreRank,
    ViewDecile,
    PreviousScore,
    NextScore,
    RecencyRank,
    TotalPostsInAnalysis,
    RelativeScore,
    ScoreTrend,
    PostProminence,
    QuestionQuality,
    PostOverview,
    CommentIntensity,
    PostTypeDescription,
    CASE 
        WHEN TotalPosts > 100 AND TotalQuestionScore > 5000 THEN 'Elite Contributor'
        WHEN TotalPosts > 50 AND TotalQuestionScore > 2000 THEN 'Active Contributor'
        WHEN TotalPosts > 10 AND TotalQuestionScore > 500 THEN 'Standard Contributor'
        ELSE 'New Contributor'
    END AS ContributorTier,
    CASE 
        WHEN Reputation > 1000000 THEN 'Legendary Reputation'
        WHEN Reputation > 100000 THEN 'High Reputation'
        WHEN Reputation > 10000 THEN 'Medium Reputation'
        ELSE 'Lower Reputation'
    END AS ReputationLevel,
    CASE 
        WHEN Score > 100 THEN 'High Performer'
        WHEN Score > 50 THEN 'Medium Performer'
        WHEN Score > 10 THEN 'Low Performer'
        ELSE 'Minimal Performer'
    END AS PerformanceTier,
    CASE 
        WHEN ViewCount IS NOT NULL AND ViewCount > 0 THEN 
            ROUND((ViewCount * 100.0) / NULLIF((SELECT MAX(ViewCount) FROM Posts), 0), 2)
        ELSE 0
    END AS ViewPercentageRank,
    DATEDIFF(DAY, LatestPostDate, CURRENT_TIMESTAMP) AS DaysSinceLastPost,
    CASE 
        WHEN LastActivityDate BETWEEN '2023-01-01' AND '2023-12-31' THEN '2023 Activity'
        WHEN LastActivityDate BETWEEN '2022-01-01' AND '2022-12-31' THEN '2022 Activity'
        WHEN LastActivityDate BETWEEN '2021-01-01' AND '2021-12-31' THEN '2021 Activity'
        ELSE 'Legacy Activity'
    END AS ActivityPeriod,
    IIF(RankByScore <= 10 AND RankByReputation <= 10, 'Top Ranked User', 'Regular User') AS UserPerformance,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = t.UserId AND b.Class = 1) THEN 'Has Gold Badge'
        ELSE 'No Gold Badge'
    END AS GoldBadgeStatus,
    IIF(ABS(PreviousScore - NextScore) > 20, 'High Score Volatility', 'Stable Score Trend') AS ScoreTrendStability,
    STRING_AGG(PostTags, ';') AS CompositeTags,
    COUNT(*) OVER (PARTITION BY UserId) AS UserPostCount,
    CASE 
        WHEN SUM(Score) OVER (PARTITION BY UserId) > 1000 THEN 'High Scoring User'
        ELSE 'Regular Scoring User'
    END AS ScoringProfile,
    CONCAT(
        'User: ', DisplayName, 
        ' | Reputation: ', Reputation, 
        ' | Total Posts: ', TotalPosts,
        ' | Questions: ', QuestionCount,
        ' | Answers: ', AnswerCount,
        ' | Latest Post: ', TO_CHAR(LatestPostDate, 'YYYY-MM-DD'),
        ' | Status: ', 
        CASE 
            WHEN DATEDIFF(DAY, LatestPostDate, CURRENT_TIMESTAMP) > 365 THEN 'Inactive'
            WHEN DATEDIFF(DAY, LatestPostDate, CURRENT_TIMESTAMP) > 180 THEN 'Semi-active'
            ELSE 'Active'
        END
    ) AS ComprehensiveUserDetail,
    CASE 
        WHEN COUNT(DISTINCT BadgeName) > 0 THEN 'Badge Recipient'
        ELSE 'No Badges'
    END AS BadgeRecipientship,
    ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalQuestionScore DESC, ScoreRank ASC) AS FinalRanking,
    RANK() OVER (ORDER BY Reputation DESC, TotalQuestionScore DESC, TotalPosts DESC) AS ComprehensiveRank,
    DENSE_RANK() OVER (ORDER BY LatestPostDate DESC) AS MostRecentRank,
    CASE 
        WHEN EXTRACT(YEAR FROM LatestPostDate) = EXTRACT(YEAR FROM CURRENT_TIMESTAMP) THEN 'Current Year Poster'
        ELSE 'Historical Poster'
    END AS PostingPeriod,
    DATEDIFF(DAY, '2010-01-01', LatestPostDate) AS DaysSinceStart,
    IIF(
        (AnswerCount > 0 OR QuestionCount > 0) AND 
        (TotalQuestionScore + TotalAnswerScore) > 0 AND 
        (TotalQuestionScore + TotalAnswerScore) > (TotalPosts * 10), 
        'High Engagement Contributor', 
        'Regular Contributor'
    ) AS EngagementLevel,
    CASE 
        WHEN ABS(AvgAnswerScore) > 3 OR (AnswerCount > 5 AND QuestionCount > 10) THEN 'High Activity'
        WHEN AnswerCount > 0 OR QuestionCount > 0 THEN 'Active'
        ELSE 'Inactive'
    END AS ActivityStatus
FROM ComplexJoinResults t
WHERE UserId IS NOT NULL
GROUP BY 
    UserId, DisplayName, Reputation, TotalPosts, QuestionCount, AnswerCount, 
    TotalQuestionScore, TotalAnswerScore, LatestPostDate, AvgAnswerScore, 
    AllQuestionTags, RankByScore, RankByReputation, RankByPostCount, BadgeName, 
    BadgeTier, TotalBadges, BadgeRank, PostId, Title, Score, ViewCount, AnswerCount,
    CommentCount, CreationDate, PostTypeId, Tags, EngagementLevel, AnswerQuality, 
    CommentActivity, PostTags, ScoreRank, ViewDecile, PreviousScore, NextScore, 
    RecencyRank, TotalPostsInAnalysis, RelativeScore, ScoreTrend, PostProminence, 
    QuestionQuality, PostOverview, CommentIntensity, PostTypeDescription
ORDER BY 
    Reputation DESC, 
    TotalQuestionScore DESC, 
    ScoreRank ASC,
    RelativeScore DESC,
    FinalRanking ASC
LIMIT 1000;