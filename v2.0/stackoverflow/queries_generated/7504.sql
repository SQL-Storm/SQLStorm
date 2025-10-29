-- {"query": "7504.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2826} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COALESCE(
            (SELECT MAX(ph.CreationDate) 
             FROM PostHistory ph 
             WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)),
            u.LastAccessDate
        ) AS LastActivityDate,
        DATEDIFF(DAY, u.CreationDate, COALESCE(MAX(p.CreationDate), u.CreationDate)) AS AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                (SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) + 
                 SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END)) / 
                NULLIF(COUNT(DISTINCT p.Id), 0)
            ELSE 0 
        END AS AvgPostScore,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 AND COUNT(DISTINCT p.Id) > 1 THEN 
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) 
            ELSE NULL 
        END AS MedianPostScore,
        STRING_AGG(DISTINCT p.Tags, ';') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, Views DESC) AS RankByReputation,
        DENSE_RANK() OVER (ORDER BY PostCount DESC) AS RankByPostCount,
        RANK() OVER (ORDER BY TotalQuestionScore DESC) AS RankByQuestionScore,
        NTILE(10) OVER (ORDER BY AVG(AvgPostScore) DESC) AS PerformanceTier,
        CASE 
            WHEN LastPostDate >= DATEADD(MONTH, -3, GETDATE()) THEN 'Active'
            WHEN LastCommentDate >= DATEADD(MONTH, -3, GETDATE()) THEN 'CommentActive'
            WHEN LastActivityDate >= DATEADD(MONTH, -3, GETDATE()) THEN 'RecentlyActive'
            ELSE 'Inactive'
        END AS ActivityStatus,
        CASE 
            WHEN PostCount >= 1000 THEN 'Veteran'
            WHEN PostCount >= 100 THEN 'Experienced'
            WHEN PostCount >= 10 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ExperienceLevel,
        CASE 
            WHEN Reputation >= 100000 THEN 'Legendary'
            WHEN Reputation >= 10000 THEN 'Master'
            WHEN Reputation >= 1000 THEN 'Expert'
            WHEN Reputation >= 100 THEN 'Advanced'
            ELSE 'Novice'
        END AS ReputationTier,
        CASE 
            WHEN BadgeCount >= 50 THEN 'AwardWinning'
            WHEN BadgeCount >= 20 THEN 'Recognized'
            WHEN BadgeCount >= 5 THEN 'Regular'
            ELSE 'New'
        END AS RecognitionLevel,
        CASE 
            WHEN AccountAgeDays > 365 THEN 'LongTerm'
            WHEN AccountAgeDays > 90 THEN 'MediumTerm'
            WHEN AccountAgeDays > 30 THEN 'ShortTerm'
            ELSE 'New'
        END AS AccountDuration
    FROM UserActivityStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ISNULL(p.Title, 'No Title') AS TagWikiTitle,
        COALESCE(p.Body, 'No Content') AS TagWikiContent,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) AS WikiAgeDays,
        CASE 
            WHEN t.Count > 1000 THEN 'HighInterest'
            WHEN t.Count > 100 THEN 'ModerateInterest'
            WHEN t.Count > 10 THEN 'LowInterest'
            ELSE 'MinimalInterest'
        END AS InterestLevel,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'ModeratorOnly'
            ELSE 'Community'
        END AS TagType,
        COUNT(DISTINCT ph.PostId) AS UsageCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN ph.PostId END) AS InitialUsageCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId END) AS EditUsageCount
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.WikiPostId
    LEFT JOIN PostHistory ph ON ph.PostId = t.WikiPostId
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, p.Title, p.Body, p.CreationDate, t.IsRequired, t.IsModeratorOnly
),
TopQuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        (SELECT COUNT(*) 
         FROM Posts a 
         WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.DeletedDate IS NULL) AS ActualAnswerCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Unanswered'
        END AS QuestionStatus,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) AS AgeInDays,
        DATEDIFF(DAY, p.LastActivityDate, GETDATE()) AS LastActivityDays,
        CASE 
            WHEN p.Score >= 100 THEN 'HighlyPopular'
            WHEN p.Score >= 10 THEN 'Popular'
            WHEN p.Score >= 0 THEN 'Neutral'
            ELSE 'Controversial'
        END AS PopularityStatus,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Trending'
            WHEN p.ViewCount > 100 THEN 'Notable'
            ELSE 'Ordinary'
        END AS VisibilityStatus,
        STRING_AGG(SUBSTRING(t.TagName, 1, 20), ', ') AS TagList,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
        RANK() OVER (ORDER BY p.ViewCount DESC) AS RankByViews,
        DENSE_RANK() OVER (ORDER BY p.AnswerCount DESC) AS RankByAnswers,
        PERCENT_RANK() OVER (ORDER BY p.FavoriteCount DESC) AS FavoritePercentile
    FROM Posts p
    INNER JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
    LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2 AND a.DeletedDate IS NULL
    LEFT JOIN Tags t ON t.TagName IN (
        SELECT value 
        FROM STRING_SPLIT(REPLACE(p.Tags, '<', ''), '>')
    )
    WHERE p.PostTypeId = 1 
    AND p.DeletedDate IS NULL
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.CreationDate, p.OwnerUserId, p.Tags, p.LastActivityDate, u.DisplayName
)
SELECT 
    'BenchmarkResults' AS ReportType,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT ru.UserId) AS ActiveUsers,
    COUNT(DISTINCT ta.TagName) AS TotalTags,
    COUNT(DISTINCT tq.QuestionId) AS TotalQuestions,
    AVG(ru.Reputation) AS AvgReputation,
    AVG(ru.PostCount) AS AvgPostCount,
    AVG(ta.Count) AS AvgTagCount,
    AVG(tq.Score) AS AvgQuestionScore,
    MAX(tq.ViewCount) AS MaxViews,
    MIN(tq.CreationDate) AS EarliestQuestion,
    MAX(tq.CreationDate) AS LatestQuestion,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND DeletedDate IS NULL) AS LiveQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND DeletedDate IS NULL) AS LiveAnswers,
    (SELECT COUNT(*) FROM Users WHERE LastAccessDate > DATEADD(MONTH, -1, GETDATE())) AS RecentActiveUsers,
    (SELECT COUNT(*) FROM Badges WHERE Date > DATEADD(MONTH, -6, GETDATE())) AS RecentBadges,
    (SELECT COUNT(*) FROM Votes WHERE VoteTypeId = 2 AND CreationDate > DATEADD(DAY, -30, GETDATE())) AS RecentUpvotes,
    (SELECT COUNT(*) FROM Votes WHERE VoteTypeId = 3 AND CreationDate > DATEADD(DAY, -30, GETDATE())) AS RecentDownvotes,
    (SELECT COUNT(*) FROM PostHistory WHERE PostHistoryTypeId IN (10, 11, 12, 13) AND CreationDate > DATEADD(DAY, -7, GETDATE())) AS RecentModActions,
    (SELECT COUNT(*) FROM Comments WHERE CreationDate > DATEADD(DAY, -7, GETDATE())) AS RecentComments,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId IN (SELECT Id FROM Users WHERE Reputation > 150000)) AS TopReputationPostCount,
    (SELECT SUM(AnswerCount) FROM Posts WHERE PostTypeId = 1 AND DeletedDate IS NULL) AS TotalAnswers,
    (SELECT COUNT(*) FROM Posts WHERE Tags IS NOT NULL AND Tags <> '' AND PostTypeId = 1) AS TaggedQuestions,
    (SELECT MAX(AccountAgeDays) FROM UserActivityStats) AS MaxAccountAgeDays,
    (SELECT AVG(AccountAgeDays) FROM UserActivityStats) AS AvgAccountAgeDays,
    (SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY PostCount) FROM UserActivityStats) AS Top5PercentPostCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId IN (SELECT Id FROM Users WHERE UpVotes > 10000)) AS HighUpvoteUsers,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId IN (SELECT Id FROM Users WHERE DownVotes > 5000)) AS HighDownvoteUsers,
    (SELECT COUNT(*) FROM Posts WHERE ViewCount > 100000) AS VeryHighViewQuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE Score > 1000) AS VeryHighScoreQuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE AnswerCount > 100) AS HighlyAnsweredQuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE CommentCount > 50) AS HighlyCommentedQuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE FavoriteCount > 100) AS HighlyFavoritedQuestionCount,
    STRING_AGG(CONCAT('Tag_', ta.TagName, ':', ta.Count), ', ') AS TagDistribution,
    STRING_AGG(CONCAT('User_', ru.UserId, ':', ru.Reputation), ', ') AS UserReputationDistribution
FROM RankedUsers ru
FULL OUTER JOIN TagAnalysis ta ON 1=1
FULL OUTER JOIN TopQuestionStats tq ON 1=1
WHERE ru.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR tq.QuestionId IS NOT NULL
HAVING COUNT(*) >= 100000 OR COUNT(*) <= 1000000
OPTION (MAXDOP 1, RECOMPILE)