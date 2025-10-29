-- {"query": "7491.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2072} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalQuestionViews,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) as TotalAnswerViews,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(DAY, u.CreationDate, GETDATE()) as AccountAgeDays,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
        NTILE(10) OVER (ORDER BY SUM(p.Score) DESC) as ScoreDecile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank
    FROM Tags t
    WHERE t.Count > 50
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
        u.Id as OwnerId,
        u.DisplayName as OwnerName,
        p.Tags,
        STRING_AGG(SUBSTRING(p.Tags, n.number, 1), ',') as IndividualTags,
        CASE 
            WHEN p.AnswerCount = 0 THEN 'Unanswered'
            WHEN p.AnswerCount = 1 THEN 'One Answer'
            WHEN p.AnswerCount > 1 THEN 'Multiple Answers'
            ELSE 'Unknown'
        END as AnswerStatus,
        CASE 
            WHEN p.Score < 0 THEN 'Below Average'
            WHEN p.Score BETWEEN 0 AND 5 THEN 'Average'
            WHEN p.Score BETWEEN 6 AND 20 THEN 'Good'
            WHEN p.Score > 20 THEN 'Excellent'
            ELSE 'Unknown'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) as UserQuestionRank
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    CROSS JOIN (
        SELECT 1 as number UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) n
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, 
             p.CreationDate, u.Id, u.DisplayName, p.Tags
),
RecentActivity AS (
    SELECT 
        ph.Id as HistoryId,
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        p.Title as PostTitle,
        ph.CreationDate,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Body Edit'
            WHEN ph.PostHistoryTypeId = 10 THEN 'Post Closed'
            WHEN ph.PostHistoryTypeId = 11 THEN 'Post Reopened'
            WHEN ph.PostHistoryTypeId = 12 THEN 'Post Deleted'
            WHEN ph.PostHistoryTypeId = 13 THEN 'Post Undeleted'
            ELSE 'Other'
        END as ActivityType,
        ROW_NUMBER() OVER (PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) as UserActivityRank
    FROM PostHistory ph
    LEFT JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.CreationDate >= DATEADD(MONTH, -6, GETDATE())
),
CombinedAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalScore,
        uas.TotalQuestionViews,
        uas.TotalAnswerViews,
        uas.CommentCount,
        uas.BadgeCount,
        uas.LastPostDate,
        uas.AccountAgeDays,
        uas.ScoreRank,
        uas.ScoreDecile,
        CASE 
            WHEN uas.QuestionCount > 100 AND uas.AnswerCount > 100 THEN 'High Activity'
            WHEN uas.QuestionCount > 50 OR uas.AnswerCount > 50 THEN 'Medium Activity'
            ELSE 'Low Activity'
        END as ActivityLevel,
        CASE 
            WHEN uas.Reputation > 100000 THEN 'Elite'
            WHEN uas.Reputation > 10000 THEN 'Advanced'
            WHEN uas.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        STRING_AGG(qa.Title, '; ') as FavoriteQuestions,
        STRING_AGG(CONCAT(qa.Title, ' (Score: ', qa.Score, ')'), '; ') as TopQuestions,
        COUNT(DISTINCT ra.PostId) as RecentActivityCount
    FROM UserActivityStats uas
    LEFT JOIN QuestionAnalysis qa ON uas.UserId = qa.OwnerId
    LEFT JOIN RecentActivity ra ON uas.UserId = ra.UserId AND ra.UserActivityRank <= 5
    GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.QuestionCount, uas.AnswerCount, 
             uas.TotalScore, uas.TotalQuestionViews, uas.TotalAnswerViews, uas.CommentCount, 
             uas.BadgeCount, uas.LastPostDate, uas.AccountAgeDays, uas.ScoreRank, uas.ScoreDecile
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.TotalScore,
    ca.TotalQuestionViews,
    ca.TotalAnswerViews,
    ca.CommentCount,
    ca.BadgeCount,
    ca.LastPostDate,
    ca.AccountAgeDays,
    ca.ScoreRank,
    ca.ScoreDecile,
    ca.ActivityLevel,
    ca.ReputationLevel,
    COALESCE(ca.FavoriteQuestions, 'No questions found') as FavoriteQuestions,
    COALESCE(ca.TopQuestions, 'No questions found') as TopQuestions,
    CASE 
        WHEN ca.TotalScore > 1000 THEN 'High Performer'
        WHEN ca.TotalScore > 500 THEN 'Mid Performer'
        WHEN ca.TotalScore > 100 THEN 'Low Performer'
        ELSE 'New User'
    END as PerformanceTier,
    COUNT(DISTINCT ta.TagName) as PopularTagCount,
    STRING_AGG(DISTINCT ta.TagName, ', ') as PopularTags,
    ISNULL(
        (SELECT COUNT(*) FROM Posts p2 
         WHERE p2.OwnerUserId = ca.UserId AND p2.PostTypeId = 1 AND p2.CreationDate > DATEADD(YEAR, -1, GETDATE())), 
        0
    ) as QuestionsLastYear,
    CASE 
        WHEN ca.QuestionCount > 0 AND ca.AnswerCount > 0 THEN 
            CAST(ca.AnswerCount AS FLOAT) / CAST(ca.QuestionCount AS FLOAT)
        ELSE 0 
    END as AnswerToQuestionRatio,
    RANK() OVER (ORDER BY ca.AccountAgeDays ASC) as SeniorityRank,
    AVG(ca.TotalScore) OVER (PARTITION BY ca.ReputationLevel) as AvgScoreByReputation,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = ca.UserId AND p3.PostTypeId = 2) as TotalAnswers,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.UserId AND v.VoteTypeId = 1) as AcceptanceCount
FROM CombinedAnalysis ca
LEFT JOIN TopTags ta ON ta.TagRank <= 10
WHERE ca.QuestionCount > 0
GROUP BY 
    ca.UserId, ca.DisplayName, ca.Reputation, ca.QuestionCount, ca.AnswerCount, 
    ca.TotalScore, ca.TotalQuestionViews, ca.TotalAnswerViews, ca.CommentCount, 
    ca.BadgeCount, ca.LastPostDate, ca.AccountAgeDays, ca.ScoreRank, ca.ScoreDecile,
    ca.ActivityLevel, ca.ReputationLevel, ca.FavoriteQuestions, ca.TopQuestions
HAVING 
    COUNT(DISTINCT ta.TagName) > 0 OR ca.QuestionCount > 0
ORDER BY 
    ca.TotalScore DESC, 
    ca.Reputation DESC,
    ca.QuestionCount DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;