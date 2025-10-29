-- {"query": "7478.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2078} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPostsByUser,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScoreByUser,
        NTILE(4) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score) as ScoreQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        COALESCE(MAX(p.LastActivityDate), u.LastAccessDate) as LastActivity,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(LEN(t.TagName) - LEN(REPLACE(t.TagName, '-', '')), 0) as HyphenCount,
        CASE WHEN t.TagName LIKE '%_%' THEN 'HasUnderscore' ELSE 'NoUnderscore' END as UnderscoreFlag,
        CASE WHEN t.TagName LIKE '%-%' THEN 'HasHyphen' ELSE 'NoHyphen' END as HyphenFlag,
        CASE WHEN t.TagName LIKE '%-%' AND t.TagName LIKE '%_%' THEN 'HasBoth' ELSE 'Other' END as SpecialCharFlag
    FROM Tags t
),
QuestionStats AS (
    SELECT 
        p.PostTypeId,
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(p.Tags, '') as Tags,
        p.LastActivityDate,
        SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2) as CleanTags,
        STRING_SPLIT(REPLACE(REPLACE(p.Tags, '<', ''), '>', '')) as TagArray,
        CASE 
            WHEN p.AnswerCount > 0 AND p.Score > 0 THEN 'ActiveWithAnswers'
            WHEN p.AnswerCount = 0 AND p.Score > 0 THEN 'ActiveNoAnswers'
            WHEN p.AnswerCount > 0 AND p.Score <= 0 THEN 'InactiveWithAnswers'
            ELSE 'Other'
        END as QuestionStatus,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysSinceLastActivity,
        CASE 
            WHEN DATEDIFF(day, p.CreationDate, p.LastActivityDate) > 365 THEN 'InactiveOverYear'
            WHEN DATEDIFF(day, p.CreationDate, p.LastActivityDate) > 180 THEN 'InactiveHalfYear'
            WHEN DATEDIFF(day, p.CreationDate, p.LastActivityDate) > 30 THEN 'InactiveMonth'
            ELSE 'Active'
        END as ActivityLevel
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    'Performance Benchmark Results' as QueryDescription,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT rs.OwnerUserId) as UniqueUsers,
    COUNT(DISTINCT qs.QuestionId) as TotalQuestions,
    COUNT(DISTINCT CASE WHEN rs.TotalPostsByUser > 1 THEN rs.OwnerUserId END) as ActiveUsers,
    AVG(rs.AvgScoreByUser) as AvgUserScore,
    MAX(rs.ScoreQuartile) as MaxScoreQuartile,
    COUNT(DISTINCT ta.TagName) as TotalTags,
    AVG(ua.TotalScore) as AvgUserTotalScore,
    COUNT(DISTINCT CASE WHEN qs.QuestionStatus = 'ActiveWithAnswers' THEN qs.QuestionId END) as ActiveQuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN qs.ActivityLevel = 'Active' THEN qs.QuestionId END) as RecentlyActiveQuestions,
    (SELECT COUNT(*) FROM Badges b 
     JOIN Users u ON b.UserId = u.Id 
     WHERE b.Date >= DATEADD(month, -6, GETDATE()) 
     AND u.Reputation > 10000) as RecentHighReputationBadges,
    COUNT(DISTINCT CASE 
        WHEN rs.ScoreQuartile = 1 AND rs.PostRank > 1 THEN rs.Id 
        WHEN rs.PrevScore IS NOT NULL AND rs.Score > rs.PrevScore THEN rs.Id 
        ELSE NULL 
    END) as RisingScorePosts,
    COUNT(DISTINCT CASE 
        WHEN ta.SpecialCharFlag IN ('HasBoth', 'HasUnderscore') THEN ta.TagName 
        ELSE NULL 
    END) as TagsWithSpecialCharacters,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL THEN p.Id 
        ELSE NULL 
    END) as NonDeletedAnswers,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id 
        ELSE NULL 
    END) as ClosedQuestions,
    SUM(CASE 
        WHEN COALESCE(rs.Score, 0) > 10 AND rs.TotalPostsByUser > 10 THEN 1 
        ELSE 0 
    END) as HighPerformingPosts,
    (SELECT COUNT(*) FROM PostHistory ph 
     WHERE ph.PostHistoryTypeId IN (10, 12, 13) 
     AND ph.CreationDate >= DATEADD(year, -1, GETDATE())) as RecentModerationActions,
    AVG(ua.AvgScore) as AvgUserAvgScore,
    COUNT(DISTINCT CASE 
        WHEN ua.Reputation > 5000 AND ua.TotalPosts > 100 THEN ua.UserId 
        ELSE NULL 
    END) as HighReputationActiveUsers,
    COUNT(DISTINCT CASE WHEN ta.HyphenCount > 0 THEN ta.TagName END) as TagsWithHyphens,
    (SELECT COUNT(*) FROM Votes v 
     WHERE v.VoteTypeId IN (2, 3) 
     AND v.CreationDate >= DATEADD(month, -3, GETDATE())) as RecentVotes,
    COUNT(DISTINCT CASE 
        WHEN rs.Score > 5 and rs.TotalPostsByUser >= 5 THEN rs.OwnerUserId 
        ELSE NULL 
    END) as StrongActivityUsers,
    COUNT(DISTINCT CASE 
        WHEN COALESCE(rs.Score, 0) < 0 AND rs.TotalPostsByUser >= 10 THEN rs.Id 
        ELSE NULL 
    END) as NegativeScorePosts,
    COUNT(DISTINCT CASE 
        WHEN LEN(COALESCE(qs.Tags, '')) > 50 THEN qs.QuestionId 
        ELSE NULL 
    END) as TagHeavyQuestions,
    COUNT(DISTINCT CASE 
        WHEN qs.DaysSinceLastActivity < 30 THEN qs.QuestionId 
        ELSE NULL 
    END) as RecentlyActiveQuestionsOnly,
    (SELECT COUNT(DISTINCT UserDisplayName) FROM PostHistory WHERE PostHistoryTypeId = 1) as UniqueEditors,
    AVG(CAST(LEN(COALESCE(qs.Title, '')) AS FLOAT)) as AvgTitleLength,
    COUNT(DISTINCT CASE 
        WHEN ua.LastActivity >= DATEADD(month, -3, GETDATE()) THEN ua.UserId 
        ELSE NULL 
    END) as RecentlyActiveUsers,
    COUNT(DISTINCT CASE 
        WHEN COALESCE(ua.Views, 0) > 1000 THEN ua.UserId 
        ELSE NULL 
    END) as HighTrafficUsers,
    (SELECT COUNT(*) FROM Posts p WHERE p.ContentLicense = 'CC BY-SA 4.0') as CCBySALicensedPosts,
    COUNT(DISTINCT CASE 
        WHEN qs.AnswerCount = 0 THEN qs.QuestionId 
        ELSE NULL 
    END) as UnansweredQuestions,
    AVG(CAST(COALESCE(qs.AnswerCount, 0) AS FLOAT)) as AvgAnswersPerQuestion,
    COUNT(DISTINCT CASE 
        WHEN COALESCE(qs.CommentCount, 0) > 10 THEN qs.QuestionId 
        ELSE NULL 
    END) as HighlyCommentedQuestions,
    COUNT(DISTINCT CASE 
        WHEN qs.FavoriteCount > 5 THEN qs.QuestionId 
        ELSE NULL 
    END) as HighlyFavoritedQuestions
FROM RankedPosts rs
FULL OUTER JOIN UserActivityStats ua ON rs.OwnerUserId = ua.UserId
FULL OUTER JOIN TagAnalysis ta ON rs.Id IS NOT NULL
FULL OUTER JOIN QuestionStats qs ON rs.Id IS NOT NULL
FULL OUTER JOIN Posts p ON rs.Id = p.Id
WHERE (rs.OwnerUserId IS NOT NULL OR ua.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR qs.QuestionId IS NOT NULL OR p.Id IS NOT NULL)