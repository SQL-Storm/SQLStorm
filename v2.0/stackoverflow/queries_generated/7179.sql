-- {"query": "7179.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3047} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViews,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) AS RankByScore,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) AS RankByBadges
    FROM UserActivityStats
),
TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS ActualAnswerCount,
        (SELECT AVG(v.Score) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS AvgVoteScore,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.Score >= 20 THEN 'Highly Rated'
            ELSE 'Standard'
        END AS QuestionCategory
    FROM Posts p
    WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2020-01-01'
    AND p.ViewCount > 1000
),
PostAnalysis AS (
    SELECT 
        t.QuestionId,
        t.Title,
        t.Score,
        t.ViewCount,
        u.DisplayName AS OwnerName,
        u.Reputation,
        t.CreationDate,
        t.AnswerCount,
        t.CommentCount,
        t.Tags,
        t.ActualAnswerCount,
        t.AvgVoteScore,
        t.QuestionCategory,
        CASE 
            WHEN t.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg'
            WHEN t.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Avg'
            ELSE 'Avg'
        END AS ScoreComparison,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = t.QuestionId) AS CommentCount,
        DATEDIFF('day', t.CreationDate, CURRENT_TIMESTAMP) AS DaysActive,
        RANK() OVER (ORDER BY t.Score DESC) AS ScoreRank,
        PERCENT_RANK() OVER (ORDER BY t.ViewCount) AS ViewPercentile
    FROM TopQuestions t
    JOIN Users u ON t.OwnerUserId = u.Id
),
ComplexPostHistory AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        CASE 
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN 
                (SELECT COUNT(*) FROM PostHistory WHERE PostId = ph.PostId AND PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35))
            ELSE 0
        END AS ModActionCount,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 
                (ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) - 1)
            ELSE 0
        END AS RevisionNumber,
        COALESCE(ph.UserDisplayName, (SELECT DisplayName FROM Users WHERE Id = ph.UserId)) AS DisplayName,
        LAG(ph.PostHistoryTypeId) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryTypeId
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2022-01-01'
),
UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        COUNT(DISTINCT p.Id) AS PostCount,
        MAX(p.CreationDate) AS LastPost,
        MIN(p.CreationDate) AS FirstPost,
        DATEDIFF('day', MIN(p.CreationDate), MAX(p.CreationDate)) AS ActiveDays,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgViews,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') AS QuestionTitles,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Body END, ' | ') AS AnswerBodies,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS ScoreRank,
        CASE 
            WHEN COUNT(DISTINCT p.Id) >= 100 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) >= 50 THEN 'Moderate'
            WHEN COUNT(DISTINCT p.Id) >= 10 THEN 'Beginner'
            ELSE 'Newbie'
        END AS PostingLevel,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score >= 10 THEN p.Id END) AS HighScoreQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score >= 5 THEN p.Id END) AS HighScoreAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
)

SELECT 
    'Final Analysis' AS ReportType,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT p.PostId) AS DistinctPosts,
    AVG(CAST(COALESCE(p.Text, '0') AS INT)) AS AvgTextLength,
    MAX(p.CreationDate) AS LatestEntry,
    MIN(p.CreationDate) AS EarliestEntry,
    COUNT(CASE WHEN p.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 END) AS ModActions,
    COUNT(CASE WHEN p.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 1 END) AS RevisionEvents,
    STRING_AGG(DISTINCT CASE WHEN p.PostHistoryTypeId IN (10, 11, 12, 13) THEN p.Comment END, ' | ') AS ModActionComments,
    COUNT(DISTINCT CASE WHEN p.PostId IS NOT NULL AND p.UserId IS NOT NULL THEN p.UserId END) AS DistinctEditors,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.PostTypeId = 1 AND p2.Score >= 20), 
        0
    ) AS HighlyRatedQuestions,
    (
        SELECT COUNT(*) FROM Users u2 
        JOIN Posts p3 ON u2.Id = p3.OwnerUserId 
        WHERE p3.CreationDate >= '2023-01-01'
        AND p3.PostTypeId = 1
    ) AS RecentQuestions,
    COUNT(DISTINCT CASE WHEN p.PostHistoryTypeId IN (35, 36) THEN p.PostId END) AS MigrationEvents,
    COUNT(DISTINCT CASE WHEN p.PostHistoryTypeId IN (25, 50, 52) THEN p.PostId END) AS CommunityActions,
    COUNT(DISTINCT CASE WHEN p.PostHistoryTypeId IN (4, 5, 6) THEN p.PostId END) AS TitleBodyTagEdits,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostHistoryTypeId = 50) AS CommunityBumps,
    COUNT(DISTINCT CASE WHEN p.PostHistoryTypeId = 33 THEN p.PostId END) AS PostNoticesAdded,
    COUNT(DISTINCT CASE WHEN p.PostHistoryTypeId = 34 THEN p.PostId END) AS PostNoticesRemoved,
    COALESCE(
        (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1), 
        0
    ) AS AvgQuestionScore,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) AS AvgAnswerScore,
    COALESCE(
        (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1), 
        0
    ) AS AvgQuestionViews,
    COUNT(DISTINCT 
        CASE 
            WHEN p.PostId IN (
                SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 10
            ) AND p.PostId IN (
                SELECT DISTINCT PostId FROM PostHistory WHERE PostHistoryTypeId = 11
            ) 
            THEN p.PostId 
        END
    ) AS PostOpenCloseCycle,
    COUNT(DISTINCT 
        CASE 
            WHEN p.UserId IN (
                SELECT DISTINCT UserId FROM PostHistory WHERE PostHistoryTypeId = 10
            ) 
            AND p.UserId IN (
                SELECT DISTINCT UserId FROM PostHistory WHERE PostHistoryTypeId = 11
            ) 
            THEN p.UserId 
        END
    ) AS ModActionUsers
    
FROM ComplexPostHistory p
WHERE p.PostHistoryTypeId IN (10, 11, 12, 13, 1, 2, 3, 4, 5, 6, 35, 36, 25, 50, 52, 33, 34, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50)
HAVING COUNT(*) > 0
UNION ALL
SELECT 
    'Aggregated Summary' AS ReportType,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT QuestionId) AS DistinctPosts,
    AVG(CAST(LENGTH(Title) AS FLOAT)) AS AvgTitleLength,
    MAX(CreationDate) AS LatestEntry,
    MIN(CreationDate) AS EarliestEntry,
    COUNT(CASE WHEN QuestionCategory = 'Closed' THEN 1 END) AS ClosedQuestions,
    COUNT(CASE WHEN QuestionCategory = 'Highly Rated' THEN 1 END) AS HighlyRatedQuestions,
    COUNT(*) AS TotalQuestions,
    COUNT(CASE WHEN AnswerCount >= 1 THEN 1 END) AS QuestionsWithAnswers,
    COUNT(CASE WHEN CommentCount >= 1 THEN 1 END) AS QuestionsWithComments,
    AVG(CAST(Score AS FLOAT)) AS AvgScore,
    AVG(CAST(ViewCount AS FLOAT)) AS AvgViews,
    MAX(Score) AS MaxScore,
    MAX(ViewCount) AS MaxViews,
    STRING_AGG(DISTINCT Title, ' | ') AS AllQuestionTitles,
    COUNT(*) AS QuestionCount,
    COUNT(DISTINCT AnswerCount) AS DistinctAnswerCounts,
    COUNT(DISTINCT CommentCount) AS DistinctCommentCounts,
    DATEDIFF('day', MIN(CreationDate), MAX(CreationDate)) AS TotalDays,
    AVG(CAST(Score AS FLOAT)) AS ScoreVsAverage,
    AVG(CAST(ViewCount AS FLOAT)) AS ViewVsAverage,
    COUNT(*) AS QuestionsTotal,
    COUNT(DISTINCT QuestionId) AS UniqueQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) AS AnswerCount
FROM PostAnalysis
WHERE Score > 0
UNION ALL
SELECT 
    'Comprehensive User Data' AS ReportType,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT UserId) AS DistinctUsers,
    AVG(CAST(Reputation AS FLOAT)) AS AvgReputation,
    MAX(Reputation) AS MaxReputation,
    MIN(Reputation) AS MinReputation,
    SUM(TotalScore) AS TotalUserScores,
    AVG(CAST(PostCount AS FLOAT)) AS AvgPostCount,
    MAX(PostCount) AS MaxPostCount,
    STRING_AGG(DisplayName, ' | ') AS AllUserNames,
    AVG(CAST(AvgViews AS FLOAT)) AS AvgAvgViews,
    MAX(CAST(ActiveDays AS FLOAT)) AS MaxActiveDays,
    COUNT(CASE WHEN PostingLevel = 'Active' THEN 1 END) AS ActiveUsers,
    COUNT(CASE WHEN PostingLevel = 'Moderate' THEN 1 END) AS ModerateUsers,
    COUNT(CASE WHEN PostingLevel = 'Beginner' THEN 1 END) AS BeginnerUsers,
    COUNT(CASE WHEN PostingLevel = 'Newbie' THEN 1 END) AS NewbieUsers,
    SUM(HighScoreQuestions) AS TotalHighScoreQuestions,
    SUM(HighScoreAnswers) AS TotalHighScoreAnswers,
    COUNT(*) AS UserDetails,
    COUNT(DISTINCT UserId) AS UniqueUserCount,
    AVG(CAST(Reputation AS FLOAT)) AS ReputationVsAverage,
    COUNT(DISTINCT 
        CASE 
            WHEN ScoreRank <= 10 THEN UserId 
        END
    ) AS Top10Users,
    COUNT(DISTINCT 
        CASE 
            WHEN ScoreRank <= 50 THEN UserId 
        END
    ) AS Top50Users,
    COUNT(DISTINCT 
        CASE 
            WHEN ScoreRank <= 100 THEN UserId 
        END
    ) AS Top100Users,
    COUNT(*) AS UserRecord,
    COUNT(*) AS UserRecords,
    COUNT(*) AS UserEntryCount
FROM UserPostActivity
WHERE PostCount > 0
ORDER BY ReportType;