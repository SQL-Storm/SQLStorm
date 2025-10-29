-- {"query": "7211.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1992} 
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
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY QuestionCount DESC) as RankByQuestions,
        NTILE(100) OVER (ORDER BY ViewCount DESC) as PercentileByViews,
        LAG(Reputation, 1) OVER (ORDER BY Reputation DESC) as PrevReputation,
        LEAD(Reputation, 1) OVER (ORDER BY Reputation DESC) as NextReputation,
        AVG(Reputation) OVER (PARTITION BY CASE WHEN Reputation > 10000 THEN 'High' ELSE 'Low' END) as AvgReputationByTier
    FROM UserStats
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.PostId) as HistoryCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN ph.PostId END) as TitleChanges,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN ph.PostId END) as BodyChanges,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) as ClosedCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.PostId END) as ReopenedCount,
        MAX(ph.CreationDate) as LastActivity,
        STRING_AGG(DISTINCT ph.Comment, ', ') as ActivityNotes,
        CASE WHEN MAX(ph.CreationDate) > DATEADD('MONTH', -6, CURRENT_TIMESTAMP) THEN 'Active' ELSE 'Inactive' END as ActivityStatus
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagType,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END as AccessLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity,
        AVG(t.Count) OVER (PARTITION BY t.IsRequired) as AvgCountByRequired
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND LENGTH(t.TagName) > 0
),
QuestionStats AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.CreationDate,
        q.OwnerUserId,
        q.Tags,
        q.OwnerDisplayName,
        q.LastActivityDate,
        DATEDIFF('DAY', q.CreationDate, q.LastActivityDate) as DaysActive,
        COALESCE(q.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        COALESCE(q.ClosedDate, CURRENT_TIMESTAMP) as CloseDateOrNow,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END as Status,
        CASE WHEN q.Score > 10 THEN 'High' WHEN q.Score > 0 THEN 'Medium' ELSE 'Low' END as ScoreCategory,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, POSITION(' ' IN t.TagName) - 1), ', ') as FirstPartTags,
        CASE WHEN EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = q.Id AND a.Score > 100) THEN 'HasHighScoreAnswer' ELSE 'NoHighScoreAnswer' END as HasHighScoreAnswer,
        LAG(q.Score, 1) OVER (ORDER BY q.Score DESC) as PrevScore,
        NTILE(4) OVER (ORDER BY q.Score DESC) as Quartile
    FROM Posts q
    LEFT JOIN Tags t ON POSITION('<' || t.TagName || '>' IN q.Tags) > 0
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.FavoriteCount, q.CreationDate, q.OwnerUserId, q.Tags, q.OwnerDisplayName, q.LastActivityDate, q.AcceptedAnswerId, q.ClosedDate
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.PostCount,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.CommentCount,
    ru.BadgeCount,
    ru.AvgPostScore,
    CASE 
        WHEN ru.Reputation > 100000 THEN 'Elite'
        WHEN ru.Reputation > 10000 THEN 'Expert'
        WHEN ru.Reputation > 1000 THEN 'Veteran'
        WHEN ru.Reputation > 100 THEN 'Novice'
        ELSE 'Beginner'
    END as ReputationTier,
    ra.HistoryCount,
    ra.TitleChanges,
    ra.BodyChanges,
    ra.ClosedCount,
    ra.ReopenedCount,
    ra.ActivityStatus,
    ta.TagName,
    ta.TagCount,
    ta.RankByPopularity,
    qs.QuestionId,
    qs.Title,
    qs.Score,
    qs.AnswerCount,
    qs.ViewCount,
    qs.DaysActive,
    qs.Status,
    qs.ScoreCategory,
    qs.Quartile,
    CASE 
        WHEN ru.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'AboveAverage'
        WHEN ru.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'BelowAverage'
        ELSE 'Average'
    END as ReputationComparison,
    CASE 
        WHEN ru.PostCount > (SELECT AVG(PostCount) FROM UserStats) THEN 'AboveAveragePosts'
        ELSE 'BelowAveragePosts'
    END as PostsComparison,
    CASE
        WHEN ru.Reputation > (SELECT AVG(Reputation) FROM Users) 
             AND ru.PostCount > (SELECT AVG(PostCount) FROM UserStats) 
             AND ru.BadgeCount > (SELECT AVG(BadgeCount) FROM UserStats)
        THEN 'HighPerformingUser'
        ELSE 'RegularUser'
    END as UserPerformanceStatus,
    COALESCE(ru.AvgReputationByTier, 0) as AvgReputationByTier,
    COALESCE(LENGTH(ru.AllTags), 0) as TotalTagLength,
    ROUND((ru.Reputation * 1.0 / NULLIF(ru.PostCount, 0)) * 100, 2) as ReputationPerPost,
    NULLIF(ru.NextReputation - ru.PrevReputation, 0) as ReputationGap,
    CASE WHEN LENGTH(ru.AllTags) IS NOT NULL THEN 'HasTags' ELSE 'NoTags' END as TagPresence,
    CURRENT_TIMESTAMP as CurrentTimestamp,
    DATEDIFF('MONTH', ru.LastPostDate, CURRENT_TIMESTAMP) as MonthsSinceLastPost,
    CASE 
        WHEN ra.ActivityStatus = 'Active' AND DATEDIFF('MONTH', ra.LastActivity, CURRENT_TIMESTAMP) < 3 THEN 'VeryActive'
        WHEN ra.ActivityStatus = 'Active' THEN 'Active'
        ELSE 'Inactive'
    END as ActivityLevel
FROM RankedUsers ru
FULL OUTER JOIN UserActivity ra ON ru.UserId = ra.UserId
FULL OUTER JOIN TagAnalysis ta ON ta.RankByPopularity BETWEEN 1 AND 50
FULL OUTER JOIN QuestionStats qs ON qs.QuestionId BETWEEN 1000 AND 2000
WHERE ru.UserId IS NOT NULL OR ra.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR qs.QuestionId IS NOT NULL
HAVING 
    (ru.Reputation > 100 OR ra.HistoryCount > 5 OR ta.TagName IS NOT NULL OR qs.QuestionId IS NOT NULL)
    AND (ru.Reputation IS NULL OR ru.Reputation > 0)
    AND (qs.Score > 0 OR qs.Score IS NULL)
ORDER BY 
    ru.Reputation DESC, 
    ra.HistoryCount DESC, 
    ta.RankByPopularity ASC,
    qs.Score DESC,
    qs.DaysActive ASC
LIMIT 1000;