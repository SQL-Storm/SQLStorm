-- {"query": "7150.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2170} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LastPostDate,
        MAX(u.LastAccessDate) as LastAccess,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') as TagList,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as AcceptedQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) as HighScoreAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId 
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes
),
Rankings AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        TotalViews,
        LastPostDate,
        LastAccess,
        TagList,
        AcceptedQuestions,
        HighScoreAnswers,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RepRank,
        RANK() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) as BadgeRank,
        NTILE(4) OVER (ORDER BY PostCount DESC) as PostQuartile,
        LAG(DisplayName) OVER (ORDER BY Reputation DESC) as PrevUser,
        LEAD(DisplayName) OVER (ORDER BY Reputation DESC) as NextUser,
        AVG(Reputation) OVER (ORDER BY Reputation ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) as RepMovingAvg,
        COUNT(*) OVER () as TotalUsers
    FROM UserStats
),
PerformanceMetrics AS (
    SELECT 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.PostCount,
        r.CommentCount,
        r.BadgeCount,
        r.QuestionCount,
        r.AnswerCount,
        r.TotalScore,
        r.TotalViews,
        r.LastPostDate,
        r.LastAccess,
        r.TagList,
        r.AcceptedQuestions,
        r.HighScoreAnswers,
        r.RepRank,
        r.ScoreRank,
        r.BadgeRank,
        r.PostQuartile,
        r.PrevUser,
        r.NextUser,
        r.RepMovingAvg,
        r.TotalUsers,
        CASE 
            WHEN r.Reputation > 10000 THEN 'Veteran'
            WHEN r.Reputation > 5000 THEN 'Experienced'
            WHEN r.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as UserLevel,
        CASE 
            WHEN r.PostCount > 500 THEN 'Highly Active'
            WHEN r.PostCount > 200 THEN 'Active'
            WHEN r.PostCount > 50 THEN 'Moderate'
            ELSE 'Casual'
        END as ActivityLevel,
        CASE 
            WHEN r.BadgeCount > 100 THEN 'Elite'
            WHEN r.BadgeCount > 50 THEN 'Experienced'
            WHEN r.BadgeCount > 10 THEN 'Competent'
            ELSE 'Novice'
        END as BadgeLevel,
        (r.Reputation + r.TotalScore + r.TotalViews) / NULLIF(r.PostCount, 0) as EfficiencyScore,
        DATEDIFF(day, r.LastPostDate, CURRENT_TIMESTAMP) as DaysSinceLastPost,
        DATEDIFF(day, r.LastAccess, CURRENT_TIMESTAMP) as DaysSinceLastAccess,
        CASE 
            WHEN r.BadgeCount > 0 AND r.QuestionCount = 0 THEN 'Non-Question User'
            WHEN r.QuestionCount > 0 AND r.AnswerCount = 0 THEN 'Question-Only User'
            WHEN r.QuestionCount > 0 AND r.AnswerCount > 0 THEN 'Question-Answer User'
            ELSE 'Unknown'
        END as EngagementType
    FROM Rankings r
),
ComplexQuery AS (
    SELECT 
        pm.UserId,
        pm.DisplayName,
        pm.Reputation,
        pm.PostCount,
        pm.CommentCount,
        pm.BadgeCount,
        pm.QuestionCount,
        pm.AnswerCount,
        pm.TotalScore,
        pm.TotalViews,
        pm.LastPostDate,
        pm.LastAccess,
        pm.TagList,
        pm.AcceptedQuestions,
        pm.HighScoreAnswers,
        pm.RepRank,
        pm.ScoreRank,
        pm.BadgeRank,
        pm.PostQuartile,
        pm.PrevUser,
        pm.NextUser,
        pm.RepMovingAvg,
        pm.TotalUsers,
        pm.UserLevel,
        pm.ActivityLevel,
        pm.BadgeLevel,
        pm.EfficiencyScore,
        pm.DaysSinceLastPost,
        pm.DaysSinceLastAccess,
        pm.EngagementType,
        LTRIM(RTRIM(UPPER(pm.TagList))) as CleanTags,
        SUBSTRING(pm.TagList, 1, 50) as First50Tags,
        CHAR_LENGTH(pm.TagList) as TagListLength,
        REPLACE(pm.TagList, ' ', '') as TagListNoSpaces,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = pm.UserId AND p.PostTypeId = 1 AND p.CreationDate >= DATEADD(month, -6, CURRENT_TIMESTAMP)) as RecentQuestions,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = pm.UserId AND p.PostTypeId = 2 AND p.CreationDate >= DATEADD(month, -6, CURRENT_TIMESTAMP)) as RecentAnswers,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = pm.UserId AND p.PostTypeId = 1) as AvgQuestionScore,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = pm.UserId AND p.PostTypeId = 2) as AvgAnswerScore,
        CASE 
            WHEN pm.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
            WHEN pm.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
            ELSE 'Average'
        END as RepComparison,
        CASE 
            WHEN pm.PostCount > (SELECT AVG(PostCount) FROM UserStats) THEN 'Above Average Posts'
            WHEN pm.PostCount < (SELECT AVG(PostCount) FROM UserStats) THEN 'Below Average Posts'
            ELSE 'Average Posts'
        END as PostComparison,
        CASE 
            WHEN pm.BadgeCount > (SELECT AVG(BadgeCount) FROM UserStats) THEN 'Above Average Badges'
            WHEN pm.BadgeCount < (SELECT AVG(BadgeCount) FROM UserStats) THEN 'Below Average Badges'
            ELSE 'Average Badges'
        END as BadgeComparison,
        (pm.PostCount * pm.Reputation) + pm.TotalScore as CompositeScore,
        (pm.QuestionCount * pm.AnswerCount) as QAPairScore,
        LOG(pm.TotalViews + 1) as LogViews,
        SQRT(pm.TotalScore) as SqrtScore,
        (pm.Reputation * pm.BadgeCount) / NULLIF(pm.PostCount, 0) as ReputationToBadgeRatio
    FROM PerformanceMetrics pm
    WHERE pm.Reputation > 0
)
SELECT 
    cq.UserId,
    cq.DisplayName,
    cq.Reputation,
    cq.PostCount,
    cq.CommentCount,
    cq.BadgeCount,
    cq.QuestionCount,
    cq.AnswerCount,
    cq.TotalScore,
    cq.TotalViews,
    cq.LastPostDate,
    cq.LastAccess,
    cq.TagList,
    cq.AcceptedQuestions,
    cq.HighScoreAnswers,
    cq.RepRank,
    cq.ScoreRank,
    cq.BadgeRank,
    cq.PostQuartile,
    cq.PrevUser,
    cq.NextUser,
    cq.RepMovingAvg,
    cq.TotalUsers,
    cq.UserLevel,
    cq.ActivityLevel,
    cq.BadgeLevel,
    cq.EfficiencyScore,
    cq.DaysSinceLastPost,
    cq.DaysSinceLastAccess,
    cq.EngagementType,
    cq.CleanTags,
    cq.First50Tags,
    cq.TagListLength,
    cq.TagListNoSpaces,
    cq.RecentQuestions,
    cq.RecentAnswers,
    cq.AvgQuestionScore,
    cq.AvgAnswerScore,
    cq.RepComparison,
    cq.PostComparison,
    cq.BadgeComparison,
    cq.CompositeScore,
    cq.QAPairScore,
    cq.LogViews,
    cq.SqrtScore,
    cq.ReputationToBadgeRatio,
    CASE 
        WHEN cq.CompositeScore > (SELECT AVG(CompositeScore) FROM ComplexQuery) THEN 1
        ELSE 0
    END as AboveAvgComposite,
    CASE 
        WHEN cq.EfficiencyScore > (SELECT AVG(EfficiencyScore) FROM ComplexQuery) THEN 1
        ELSE 0
    END as AboveAvgEfficiency,
    CASE 
        WHEN cq.ReputationToBadgeRatio > (SELECT AVG(ReputationToBadgeRatio) FROM ComplexQuery) THEN 1
        ELSE 0
    END as AboveAvgRepBadgeRatio
FROM ComplexQuery cq
WHERE cq.Reputation BETWEEN 100 AND 100000
    AND cq.PostCount > 0
    AND cq.TagList IS NOT NULL
    AND cq.TagList != ''
ORDER BY cq.CompositeScore DESC, cq.Reputation DESC, cq.EfficiencyScore DESC
LIMIT 1000;