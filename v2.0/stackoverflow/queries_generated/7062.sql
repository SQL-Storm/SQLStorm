-- {"query": "7062.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1365} 
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
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT c.Id) DESC) as CommentRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        STRING_AGG(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') WITHIN GROUP (ORDER BY p.Id) as AllTags
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
    AND p.CreationDate > '2020-01-01'
    AND p.Score > 100
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, p.OwnerUserId, u.DisplayName
),
ComplexAnalytics AS (
    SELECT 
        ta.UserId,
        ta.DisplayName,
        ta.Reputation,
        ta.PostCount,
        ta.CommentCount,
        ta.BadgeCount,
        ta.PostRank,
        ta.CommentRank,
        COALESCE(tq.Score, 0) as TopScore,
        COALESCE(tq.ViewCount, 0) as TopViewCount,
        COALESCE(tq.AnswerCount, 0) as TopAnswerCount,
        COALESCE(tq.CommentCount, 0) as TopCommentCount,
        tq.Title as TopQuestionTitle,
        CASE 
            WHEN ta.PostCount > 100 THEN 'Elite'
            WHEN ta.PostCount > 50 THEN 'Advanced'
            WHEN ta.PostCount > 10 THEN 'Regular'
            ELSE 'Beginner'
        END as ExperienceLevel,
        CASE 
            WHEN ta.Reputation > 100000 THEN 'Legendary'
            WHEN ta.Reputation > 50000 THEN 'Master'
            WHEN ta.Reputation > 10000 THEN 'Expert'
            ELSE 'Intermediate'
        END as ReputationLevel,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ta.UserId AND p2.PostTypeId = 2) as AnswerCount,
        (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = ta.UserId AND p3.PostTypeId = 1 AND p3.Score > 0) as PositiveQuestionCount,
        (SELECT AVG(Score) FROM Posts p4 WHERE p4.OwnerUserId = ta.UserId AND p4.PostTypeId = 1) as AvgQuestionScore,
        (SELECT MAX(Score) FROM Posts p5 WHERE p5.OwnerUserId = ta.UserId AND p5.PostTypeId = 1) as MaxQuestionScore,
        (ta.PostCount + ta.CommentCount) as TotalActivity,
        (ta.PostCount * 1.5 + ta.CommentCount * 0.5 + ta.BadgeCount * 10) as ActivityWeightedScore
    FROM UserActivityStats ta
    LEFT JOIN TopQuestions tq ON ta.UserId = tq.OwnerUserId
    WHERE ta.Reputation > 5000
),
FinalAnalysis AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY ActivityWeightedScore DESC) as ActivityRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as ReputationRank,
        NTILE(4) OVER (ORDER BY ActivityWeightedScore DESC) as Quartile,
        ROW_NUMBER() OVER (ORDER BY TotalActivity DESC) as ActivityOrder,
        LAG(DisplayName, 1) OVER (ORDER BY ActivityWeightedScore DESC) as PreviousTopUser,
        LEAD(DisplayName, 1) OVER (ORDER BY ActivityWeightedScore DESC) as NextTopUser,
        AVG(ActivityWeightedScore) OVER (ORDER BY ActivityWeightedScore DESC ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAvgScore,
        MIN(ActivityWeightedScore) OVER (ORDER BY ActivityWeightedScore DESC) as MinScore,
        MAX(ActivityWeightedScore) OVER (ORDER BY ActivityWeightedScore DESC) as MaxScore,
        COUNT(*) OVER () as TotalUsers,
        (ActivityWeightedScore - MIN(ActivityWeightedScore) OVER ()) / 
        (MAX(ActivityWeightedScore) OVER () - MIN(ActivityWeightedScore) OVER ()) * 100 as ScorePercentile
    FROM ComplexAnalytics
)
SELECT 
    DisplayName,
    Reputation,
    PostCount,
    CommentCount,
    BadgeCount,
    ExperienceLevel,
    ReputationLevel,
    ActivityWeightedScore,
    ActivityRank,
    ReputationRank,
    Quartile,
    TotalActivity,
    ScorePercentile,
    CASE 
        WHEN ScorePercentile > 90 THEN 'Top 10%'
        WHEN ScorePercentile > 75 THEN 'Top 25%'
        WHEN ScorePercentile > 50 THEN 'Top 50%'
        ELSE 'Below Average'
    END as PerformanceTier,
    COALESCE(TopQuestionTitle, 'No Top Question') as TopQuestion,
    COALESCE(TopScore, 0) as TopScore,
    COALESCE(TopViewCount, 0) as TopViewCount,
    PreviousTopUser,
    NextTopUser,
    MovingAvgScore
FROM FinalAnalysis
WHERE 
    ActivityWeightedScore > (
        SELECT AVG(ActivityWeightedScore) FROM FinalAnalysis
    )
    AND Reputation > (
        SELECT AVG(Reputation) FROM FinalAnalysis
    )
    AND (PostCount > 0 OR CommentCount > 0 OR BadgeCount > 0)
ORDER BY ActivityWeightedScore DESC
LIMIT 100;