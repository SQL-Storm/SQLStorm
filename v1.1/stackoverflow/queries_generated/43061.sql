-- {"query": "43061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 822} 

WITH UserReputationSummary AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostActivitySummary AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COUNT(ph.Id) AS TotalEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN ph.Id END) AS NegativeFeedback
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount
    HAVING COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN ph.Id END) > 0
),
FinalBenchmark AS (
    SELECT 
        urs.DisplayName,
        urs.Reputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        urs.TotalPosts,
        urs.AvgPostScore,
        urs.TotalQuestions,
        urs.TotalAnswers,
        SUM(pas.Score) AS TotalQuestionScore,
        AVG(pas.ViewCount) AS AvgQuestionViewCount,
        SUM(pas.TotalEdits) AS TotalEditsOnQuestions,
        SUM(pas.NegativeFeedback) AS TotalNegativeFeedbackOnQuestions
    FROM UserReputationSummary urs
    INNER JOIN PostActivitySummary pas ON urs.Id = pas.OwnerUserId
    GROUP BY urs.DisplayName, urs.Reputation, urs.GoldBadges, urs.SilverBadges, urs.BronzeBadges, urs.TotalPosts, urs.AvgPostScore, urs.TotalQuestions, urs.TotalAnswers
)
SELECT 
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalPosts,
    AvgPostScore,
    TotalQuestions,
    TotalAnswers,
    TotalQuestionScore,
    AvgQuestionViewCount,
    TotalEditsOnQuestions,
    TotalNegativeFeedbackOnQuestions,
    (TotalQuestionScore + AvgQuestionViewCount * 1.5 + TotalEditsOnQuestions * 0.5 - TotalNegativeFeedbackOnQuestions * 2) AS PerformanceIndex
FROM FinalBenchmark
ORDER BY PerformanceIndex DESC
LIMIT 10;
