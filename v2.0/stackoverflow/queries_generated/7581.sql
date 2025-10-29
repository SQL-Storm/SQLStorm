-- {"query": "7581.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2594} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(DAY, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END as RepLevel,
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END as PostTypeDesc,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'WellVoted'
            WHEN p.Score > 10 THEN 'ModeratelyVoted'
            WHEN p.Score >= 0 THEN 'LowVoted'
            ELSE 'NegativeScore'
        END as VoteCategory,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as DaysOld,
        NULLIF(p.AnswerCount, 0) as HasAnswers,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Open'
        END as PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as PostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LAG(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevViews,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        MAX(p.Score) OVER (PARTITION BY p.OwnerUserId) as MaxUserScore
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
UserPostSummary AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as Answers,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        MIN(p.CreationDate) as FirstPostDate,
        MAX(p.CreationDate) as LastPostDate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore,
        STRING_AGG(p.Title, '; ') as AllPostTitles,
        STRING_AGG(p.Tags, '|') as AllPostTags,
        COUNT(DISTINCT YEAR(p.CreationDate)) as YearsActive,
        DATEDIFF(DAY, MIN(p.CreationDate), MAX(p.CreationDate)) as ActivePeriodDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.Comments,
    uas.Badges,
    uas.LastPostDate,
    uas.AccountAgeDays,
    uas.RepLevel,
    uas.AvgPostScore,
    uas.AllTags,
    CASE 
        WHEN uas.Reputation >= 10000 AND uas.TotalPosts >= 50 THEN 'PowerUser'
        WHEN uas.Reputation >= 1000 AND uas.TotalPosts >= 20 THEN 'ActiveUser'
        WHEN uas.Reputation >= 100 AND uas.TotalPosts >= 5 THEN 'RegularUser'
        WHEN uas.Reputation <= 100 AND uas.TotalPosts <= 1 THEN 'NewUser'
        ELSE 'StandardUser'
    END as UserCategory,
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.CommentCount,
    pa.AnswerCount,
    pa.CreationDate,
    pa.PostTypeDesc,
    pa.VoteCategory,
    pa.DaysOld,
    pa.HasAnswers,
    pa.HasAcceptedAnswer,
    pa.PostStatus,
    pa.PostRank,
    pa.ScoreRank,
    pa.ScoreQuartile,
    pa.PrevScore,
    pa.PrevViews,
    pa.AvgUserScore,
    pa.TotalUserPosts,
    pa.MaxUserScore,
    ups.TotalPosts as UserTotalPosts,
    ups.Questions as UserQuestions,
    ups.Answers as UserAnswers,
    ups.AvgScore as UserAvgScore,
    ups.MaxScore as UserMaxScore,
    ups.FirstPostDate as UserFirstPostDate,
    ups.LastPostDate as UserLastPostDate,
    ups.UserCategory as UserCategoryDetailed,
    CASE 
        WHEN pa.Score > ups.MaxScore THEN 'AboveUserMax'
        WHEN pa.Score > ups.AvgScore THEN 'AboveUserAvg'
        WHEN pa.Score < ups.AvgScore THEN 'BelowUserAvg'
        ELSE 'AtUserAvg'
    END as ScoreComparison,
    CASE 
        WHEN pa.PostStatus = 'Open' AND pa.DaysOld > 30 THEN 'OldOpenPost'
        WHEN pa.PostStatus = 'Closed' AND pa.DaysOld > 60 THEN 'OldClosedPost'
        WHEN pa.PostStatus = 'CommunityOwned' AND pa.DaysOld > 100 THEN 'OldCommunityOwnedPost'
        ELSE 'RecentOrActive'
    END as PostLifecycleStage,
    DENSE_RANK() OVER (ORDER BY pa.Score DESC) as GlobalScoreRank,
    PERCENT_RANK() OVER (ORDER BY pa.Score DESC) as ScorePercentileRank,
    CUME_DIST() OVER (ORDER BY pa.Score DESC) as ScoreCumulativeDistribution,
    LAG(pa.Score, 1) OVER (ORDER BY pa.PostId) as PreviousPostScore,
    LEAD(pa.Score, 1) OVER (ORDER BY pa.PostId) as NextPostScore,
    LAG(pa.ViewCount, 1) OVER (ORDER BY pa.PostId) as PreviousPostViews,
    CASE 
        WHEN pa.PostRank = 1 THEN 'MostRecent'
        WHEN pa.PostRank = 2 THEN 'SecondMostRecent'
        WHEN pa.PostRank = 3 THEN 'ThirdMostRecent'
        WHEN pa.PostRank <= 5 THEN 'Top5Posts'
        ELSE 'OtherPost'
    END as PostRecencyTier,
    CASE 
        WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveQuestionAverage'
        WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'AboveAnswerAverage'
        ELSE 'BelowAverage'
    END as QuestionAnswerScoreTier,
    CASE 
        WHEN pa.Score >= 100 THEN 'FeaturedPost'
        WHEN pa.Score >= 50 THEN 'GoodPost'
        WHEN pa.Score >= 10 THEN 'AveragePost'
        WHEN pa.Score >= 0 THEN 'LowPost'
        ELSE 'NegativePost'
    END as PostQualityTier,
    IIF(pa.Score <> 0, pa.ViewCount / pa.Score, 0) as ViewsPerScore,
    IIF(ups.FirstPostDate = ups.LastPostDate, 'SinglePostUser', 'MultiPostUser') as UserActivityPattern,
    DATEDIFF(DAY, ups.FirstPostDate, ups.LastPostDate) as UserActivePeriod,
    COALESCE(pa.Tags, 'NoTags') as PostTags,
    CASE 
        WHEN pa.Tags IS NULL OR pa.Tags = '' THEN 0
        ELSE LEN(pa.Tags) - LEN(REPLACE(pa.Tags, '<', '')) 
    END as TagCount,
    CASE 
        WHEN pa.PostStatus = 'Open' THEN DATEDIFF(DAY, pa.CreationDate, GETDATE())
        ELSE DATEDIFF(DAY, pa.CreationDate, COALESCE(pa.ClosedDate, pa.CommunityOwnedDate))
    END as PostDurationDays,
    NULLIF(pa.AnswerCount, 0) as AnswerCountNotNull,
    NULLIF(pa.CommentCount, 0) as CommentCountNotNull,
    ISNULL(pa.AcceptedAnswerId, 0) as AcceptanceFlag,
    COALESCE(pa.Score, 0) + COALESCE(pa.ViewCount, 0) + COALESCE(pa.CommentCount, 0) as CombinedActivityScore,
    CASE 
        WHEN pa.Score >= 100 AND pa.ViewCount >= 1000 THEN 'HighImpact'
        WHEN pa.Score >= 50 AND pa.ViewCount >= 500 THEN 'MediumImpact'
        WHEN pa.Score >= 10 AND pa.ViewCount >= 100 THEN 'LowImpact'
        ELSE 'MinimalImpact'
    END as PostImpactTier,
    RANK() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.CreationDate) as UserSequenceNumber,
    ROW_NUMBER() OVER (ORDER BY pa.Score DESC, pa.CreationDate DESC) as OverallRank,
    DENSE_RANK() OVER (ORDER BY pa.OwnerUserId) as UserIdRank
FROM UserActivityStats uas
INNER JOIN PostAnalysis pa ON uas.UserId = pa.OwnerUserId
INNER JOIN UserPostSummary ups ON uas.UserId = ups.UserId
WHERE uas.UserId IS NOT NULL 
    AND pa.PostId IS NOT NULL 
    AND ups.UserId IS NOT NULL
    AND (pa.Score > 0 OR pa.ViewCount > 0 OR pa.CommentCount > 0)
    AND (pa.PostStatus = 'Open' OR pa.PostStatus = 'Closed')
    AND pa.DaysOld BETWEEN 1 AND 365
    AND uas.Reputation >= 0
    AND pa.Score BETWEEN -100 AND 1000
ORDER BY pa.Score DESC, pa.CreationDate DESC
OFFSET 0 ROWS
FETCH NEXT 5000 ROWS ONLY;