-- {"query": "7643.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1998} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostTypeDesc,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 10 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        COALESCE(LEN(p.Tags), 0) as TagLength,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankByType
    FROM Posts p
    WHERE p.CreationDate >= '2022-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.Count > 50
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT vh.Id) as HistoryCount,
        COUNT(DISTINCT CASE WHEN vh.PostHistoryTypeId = 1 THEN vh.Id END) as TitleEdits,
        COUNT(DISTINCT CASE WHEN vh.PostHistoryTypeId = 2 THEN vh.Id END) as BodyEdits,
        COUNT(DISTINCT CASE WHEN vh.PostHistoryTypeId = 10 THEN vh.Id END) as Closures,
        COUNT(DISTINCT CASE WHEN vh.PostHistoryTypeId = 11 THEN vh.Id END) as Reopens
    FROM Users u
    LEFT JOIN PostHistory vh ON u.Id = vh.UserId
    WHERE u.Reputation > 500
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ComplexVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId IN (2,3) THEN 'Vote'
            WHEN v.VoteTypeId IN (8,9) THEN 'Bounty'
            ELSE 'Other'
        END as VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) as VoteSequence
    FROM Votes v
    WHERE v.CreationDate >= '2023-01-01'
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalRecords,
    (SELECT COUNT(*) FROM Users) as TotalUsers,
    (SELECT COUNT(*) FROM Posts) as TotalPosts,
    (SELECT COUNT(*) FROM Comments) as TotalComments,
    (SELECT COUNT(*) FROM Badges) as TotalBadges,
    (SELECT COUNT(*) FROM PostHistory) as TotalHistory,
    (SELECT COUNT(*) FROM Tags) as TotalTags,
    (SELECT COUNT(*) FROM Votes) as TotalVotes,
    COUNT(DISTINCT ua.UserId) as ActiveUsers,
    COUNT(DISTINCT pa.PostId) as ActivePosts,
    AVG(ust.Reputation) as AvgReputation,
    MAX(ust.Reputation) as MaxReputation,
    MIN(ust.Reputation) as MinReputation,
    COUNT(DISTINCT CASE WHEN ust.Reputation > 10000 THEN ust.UserId END) as EliteUsers,
    COUNT(DISTINCT CASE WHEN ust.PostCount > 100 THEN ust.UserId END) as HighPostUsers,
    COUNT(DISTINCT CASE WHEN ust.BadgeCount > 50 THEN ust.UserId END) as BadgeAchievers,
    COUNT(DISTINCT pa.PostId) as QuestionCount,
    COUNT(DISTINCT CASE WHEN pa.PostTypeId = 2 THEN pa.PostId END) as AnswerCount,
    AVG(pa.Score) as AvgPostScore,
    MAX(pa.Score) as MaxPostScore,
    MIN(pa.Score) as MinPostScore,
    SUM(pa.ViewCount) as TotalViews,
    COUNT(DISTINCT ta.TagName) as TagCount,
    AVG(ta.TagCount) as AvgTagCount,
    SUM(CASE WHEN ta.TagPopularity = 'Popular' THEN 1 ELSE 0 END) as PopularTags,
    COUNT(DISTINCT CASE WHEN ua.TitleEdits > 10 THEN ua.UserId END) as ActiveEditors,
    COUNT(DISTINCT CASE WHEN ua.Closures > 5 THEN ua.UserId END) as ActiveClosers,
    COUNT(DISTINCT CASE WHEN cv.VoteCategory = 'Bounty' THEN cv.PostId END) as BountyPosts,
    (SELECT COUNT(*) FROM PostHistoryTypes) as HistoryTypes,
    (SELECT COUNT(*) FROM VoteTypes) as VoteTypes,
    (SELECT COUNT(*) FROM PostTypes) as PostTypes,
    (SELECT COUNT(*) FROM LinkTypes) as LinkTypes,
    COUNT(DISTINCT CASE WHEN pa.ScoreRankByType <= 10 THEN pa.PostId END) as TopScoringPosts,
    COUNT(DISTINCT CASE WHEN ust.ReputationRank <= 50 THEN ust.UserId END) as TopReputationUsers,
    COUNT(DISTINCT CASE WHEN pa.Score > 50 AND pa.Score <= 100 THEN pa.PostId END) as MediumScorePosts,
    COUNT(DISTINCT CASE WHEN pa.Score <= 50 THEN pa.PostId END) as LowScorePosts,
    COUNT(DISTINCT CASE WHEN pa.AnswerCount > 10 THEN pa.PostId END) as HighlyAnsweredPosts,
    COUNT(DISTINCT CASE WHEN pa.CommentCount > 20 THEN pa.PostId END) as HighlyCommentedPosts,
    AVG(CASE WHEN pa.Tags IS NOT NULL THEN LEN(pa.Tags) ELSE 0 END) as AvgTagLength,
    COUNT(DISTINCT CASE WHEN pa.Tags LIKE '%<%' THEN pa.PostId END) as PostsWithTags,
    COUNT(DISTINCT CASE WHEN pa.Tags IS NULL THEN pa.PostId END) as PostsWithoutTags,
    COUNT(DISTINCT CASE WHEN pa.TagLength > 100 THEN pa.PostId END) as LongTagPosts,
    COUNT(DISTINCT CASE WHEN pa.TagLength < 20 THEN pa.PostId END) as ShortTagPosts,
    SUM(CASE WHEN pa.Score > 100 THEN pa.ViewCount ELSE 0 END) as HighScoreViews,
    SUM(CASE WHEN pa.Score <= 100 THEN pa.ViewCount ELSE 0 END) as LowScoreViews
FROM UserStats ust
FULL OUTER JOIN UserActivity ua ON ust.UserId = ua.UserId
FULL OUTER JOIN PostAnalysis pa ON ust.UserId = pa.OwnerUserId
FULL OUTER JOIN TagAnalysis ta ON ust.UserId = ta.ExcerptPostId
FULL OUTER JOIN ComplexVotes cv ON ust.UserId = cv.UserId
WHERE ust.Reputation > 100
GROUP BY 
    ust.Reputation,
    pa.Score,
    ta.TagCount,
    pa.PostTypeId,
    pa.AnswerCount,
    pa.CommentCount,
    pa.Tags,
    pa.ScoreRankByType,
    pa.TagLength,
    CASE WHEN ust.UserId IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN ua.UserId IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN pa.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN ta.TagName IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN cv.PostId IS NOT NULL THEN 1 ELSE 0 END
HAVING 
    COUNT(*) > 0
    AND COUNT(DISTINCT ust.UserId) > 0
    AND (COUNT(DISTINCT pa.PostId) > 0 OR COUNT(DISTINCT ta.TagName) > 0)
    AND (COUNT(DISTINCT ua.UserId) > 0 OR COUNT(DISTINCT cv.PostId) > 0)
    AND (COUNT(DISTINCT ust.UserId) + COUNT(DISTINCT pa.PostId) + COUNT(DISTINCT ta.TagName) + COUNT(DISTINCT ua.UserId) + COUNT(DISTINCT cv.PostId)) > 0
ORDER BY 
    ust.Reputation DESC,
    pa.Score DESC,
    ta.TagCount DESC,
    COUNT(*) DESC
LIMIT 1000;