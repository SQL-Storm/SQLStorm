-- {"query": "29089.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2337} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) LIKE '%<%>%', ', ') as TagUsage,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Highly Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Moderate'
            ELSE 'Low'
        END as ActivityLevel,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPosts,
        AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.Score > 10 THEN p.Id END) as HighScorePosts,
        COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) as PopularPosts,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') as QuestionTitles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01 00:00:00'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        u.DisplayName as OwnerName,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        COALESCE(p.ClosedDate, '1900-01-01') as IsClosed,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered'
        END as QuestionStatus,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) as ViewPercentile,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserQuestionNumber,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        (p.Score - AVG(p.Score) OVER (PARTITION BY p.OwnerUserId)) / NULLIF(STDDEV(p.Score) OVER (PARTITION BY p.OwnerUserId), 0) as ZScore,
        DATEDIFF(DAY, p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate)) as DaysToResolution
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= '2020-01-01 00:00:00'
),
AnswerStats AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        a.LastEditDate,
        a.Body,
        CASE 
            WHEN a.Score > 10 THEN 'High Value'
            WHEN a.Score > 5 THEN 'Medium Value'
            ELSE 'Low Value'
        END as ValueCategory,
        CASE 
            WHEN a.LastEditDate > a.CreationDate THEN 'Edited'
            ELSE 'Not Edited'
        END as EditStatus,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank,
        COUNT(*) OVER (PARTITION BY a.ParentId) as TotalAnswers,
        AVG(a.Score) OVER (PARTITION BY a.ParentId) as AvgAnswerScore,
        MAX(a.Score) OVER (PARTITION BY a.ParentId) as MaxAnswerScore,
        NTILE(4) OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as QualityQuartile
    FROM Posts a
    WHERE a.PostTypeId = 2
    AND a.CreationDate >= '2020-01-01 00:00:00'
),
CombinedAnalysis AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        COALESCE(qs.QuestionId, 0) as SampleQuestionId,
        qs.Title as SampleQuestionTitle,
        qs.Score as SampleQuestionScore,
        qs.ViewCount as SampleQuestionViews,
        qs.QuestionStatus,
        qs.ScoreRank,
        qs.ViewPercentile,
        COALESCE(COUNT(DISTINCT asa.AnswerId), 0) as AnswerCountForSampleQuestion,
        AVG(asa.Score) as AvgAnswerScoreForSampleQuestion,
        MAX(asa.Score) as MaxAnswerScoreForSampleQuestion,
        CASE 
            WHEN EXISTS(SELECT 1 FROM Posts p WHERE p.ParentId = qs.QuestionId AND p.PostTypeId = 2 AND p.OwnerUserId = ua.UserId) 
            THEN 'Yes'
            ELSE 'No'
        END as UserHasAnsweredSampleQuestion,
        COALESCE(ua.HighScorePosts, 0) as HighScoreQuestionCount,
        COALESCE(ua.PopularPosts, 0) as PopularQuestionCount,
        COALESCE(ua.AvgPostScore, 0) as AveragePostScore,
        COALESCE(ua.RankByPosts, 0) as RankInPostActivity,
        CASE 
            WHEN ua.PostCount = 0 OR ua.QuestionCount = 0 THEN 'No Questions'
            WHEN ua.QuestionCount > 0 AND ua.AnswerCount = 0 THEN 'Question Only'
            WHEN ua.QuestionCount > 0 AND ua.AnswerCount > 0 THEN 'Active'
            ELSE 'Inactive'
        END as EngagementLevel,
        u.DisplayName as UserDisplayName,
        'Analysis Result' as ReportType
    FROM UserActivityStats ua
    LEFT JOIN QuestionStats qs ON ua.UserId = qs.OwnerUserId
    LEFT JOIN AnswerStats asa ON qs.QuestionId = asa.QuestionId
    LEFT JOIN Users u ON ua.UserId = u.Id
    WHERE ua.PostCount >= 10
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, ua.QuestionCount, ua.AnswerCount, 
             qs.QuestionId, qs.Title, qs.Score, qs.ViewCount, qs.QuestionStatus, qs.ScoreRank, 
             qs.ViewPercentile, ua.HighScorePosts, ua.PopularPosts, ua.AvgPostScore, ua.RankByPosts
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostCount,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.SampleQuestionId,
    ca.SampleQuestionTitle,
    ca.SampleQuestionScore,
    ca.SampleQuestionViews,
    ca.QuestionStatus,
    ca.ScoreRank,
    ca.ViewPercentile,
    ca.AnswerCountForSampleQuestion,
    ca.AvgAnswerScoreForSampleQuestion,
    ca.MaxAnswerScoreForSampleQuestion,
    ca.UserHasAnsweredSampleQuestion,
    ca.HighScoreQuestionCount,
    ca.PopularQuestionCount,
    ca.AveragePostScore,
    ca.RankInPostActivity,
    ca.EngagementLevel,
    ca.UserDisplayName,
    ca.ReportType,
    CASE 
        WHEN ca.Reputation > 10000 THEN 'Diamond'
        WHEN ca.Reputation > 5000 THEN 'Platinum'
        WHEN ca.Reputation > 1000 THEN 'Gold'
        WHEN ca.Reputation > 100 THEN 'Silver'
        ELSE 'Bronze'
    END as ReputationTier,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0) as TotalQuestions,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END), 0) as TotalAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.Id END) as TotalVotes,
    ROUND(COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) * 100.0 / NULLIF(COUNT(DISTINCT v.Id), 0), 2) as UpVotePercentage,
    STRING_AGG(DISTINCT CASE WHEN b.Name LIKE '%%Year%' THEN b.Name END, ', ') as YearlyBadgeNames,
    STRING_AGG(DISTINCT CASE WHEN p.Tags IS NOT NULL THEN SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) END, '|' ) as SampleTags,
    CASE 
        WHEN ca.PostCount > 50 THEN 'Power User'
        WHEN ca.PostCount > 20 THEN 'Regular User'
        WHEN ca.PostCount > 5 THEN 'Occasional User'
        ELSE 'New User'
    END as UserCategory
FROM CombinedAnalysis ca
LEFT JOIN Posts p ON ca.UserId = p.OwnerUserId
LEFT JOIN Votes v ON ca.UserId = v.UserId
LEFT JOIN Badges b ON ca.UserId = b.UserId
WHERE ca.UserId IN (SELECT UserId FROM UserActivityStats WHERE PostCount >= 100)
GROUP BY 
    ca.UserId, ca.DisplayName, ca.Reputation, ca.PostCount, ca.QuestionCount, ca.AnswerCount,
    ca.SampleQuestionId, ca.SampleQuestionTitle, ca.SampleQuestionScore, ca.SampleQuestionViews,
    ca.QuestionStatus, ca.ScoreRank, ca.ViewPercentile, ca.AnswerCountForSampleQuestion,
    ca.AvgAnswerScoreForSampleQuestion, ca.MaxAnswerScoreForSampleQuestion, 
    ca.UserHasAnsweredSampleQuestion, ca.HighScoreQuestionCount, ca.PopularQuestionCount,
    ca.AveragePostScore, ca.RankInPostActivity, ca.EngagementLevel, ca.UserDisplayName, ca.ReportType
HAVING COUNT(*) > 0
ORDER BY ca.PostCount DESC
LIMIT 1000;