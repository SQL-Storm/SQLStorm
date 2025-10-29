-- {"query": "7885.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2698} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LatestPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') WITHIN GROUP (ORDER BY p.CreationDate) as AllTags,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation,
        RANK() OVER (ORDER BY BadgeCount DESC) as RankByBadges,
        DENSE_RANK() OVER (ORDER BY CommentCount DESC) as RankByComments
    FROM UserStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END as VoteCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            WHEN p.ViewCount > 0 THEN 'Low'
            ELSE 'NoViews'
        END as Popularity,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as PostsPerUser,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as PostRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2020-01-01' AND p.CreationDate < '2024-01-01'
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PreviousCount,
        LAG(t.Count, 2) OVER (ORDER BY t.Count DESC) as PreviousCount2,
        (t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC)) / NULLIF(LAG(t.Count, 1) OVER (ORDER BY t.Count DESC), 0) * 100 as GrowthRate,
        RANK() OVER (ORDER BY t.Count DESC) as RankByCount
    FROM Tags t
),
ComplexVoting AS (
    SELECT 
        v.Id as VoteId,
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        p.Score as PostScore,
        p.Title as PostTitle,
        u.DisplayName as VoterName,
        CASE 
            WHEN v.VoteTypeId = 2 THEN 'Upvote'
            WHEN v.VoteTypeId = 3 THEN 'Downvote'
            ELSE 'Other'
        END as VoteType,
        CASE 
            WHEN v.VoteTypeId = 2 AND p.Score > 0 THEN 'PositiveEffect'
            WHEN v.VoteTypeId = 3 AND p.Score < 0 THEN 'NegativeEffect'
            WHEN v.VoteTypeId = 2 AND p.Score = 0 THEN 'NeutralEffect'
            ELSE 'MixedEffect'
        END as VoteImpact,
        DENSE_RANK() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate ASC) as VoteOrder,
        COUNT(*) OVER (PARTITION BY v.PostId) as TotalVotes,
        AVG(v.CreationDate) OVER (PARTITION BY v.PostId) as AvgVoteDate,
        (SELECT COUNT(*) 
         FROM Votes v2 
         WHERE v2.PostId = v.PostId AND v2.UserId = v.UserId) as UserVotesOnPost,
        ROW_NUMBER() OVER (ORDER BY v.CreationDate DESC) as RecentVoteId
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    LEFT JOIN Users u ON v.UserId = u.Id
    WHERE v.CreationDate >= '2020-01-01' AND v.CreationDate < '2024-01-01'
)

SELECT 
    'Performance Benchmarks Report' as ReportName,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT ru.UserId) as DistinctUsers,
    COUNT(DISTINCT pa.PostId) as DistinctPosts,
    COUNT(DISTINCT ts.TagName) as DistinctTags,
    COUNT(DISTINCT cv.VoteId) as TotalVotes,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) as AnswerCount,
    (SELECT AVG(Reputation) FROM Users) as AvgUserReputation,
    (SELECT AVG(Score) FROM Posts) as AvgPostScore,
    (SELECT AVG(Score) FROM Votes WHERE VoteTypeId IN (2,3)) as AvgVoteScore,
    (SELECT STRING_AGG(UPPER(TRIM(SUBSTRING(Title, 1, 10))), ', ') 
     FROM Posts 
     WHERE CreationDate >= '2023-01-01' 
     AND EXISTS (SELECT 1 FROM Users u WHERE u.Id = Posts.OwnerUserId AND u.Reputation > 5000)) as RecentHighRepPostTitles,
    (SELECT CONCAT(MIN(CreationDate), ' to ', MAX(CreationDate)) 
     FROM Posts 
     WHERE CreationDate >= '2020-01-01' 
     AND EXISTS (SELECT 1 FROM Users u WHERE u.Id = Posts.OwnerUserId AND u.Reputation > 1000)) as PostDateRange,
    (SELECT STRING_AGG(CONCAT(DisplayName, ':', BadgeCount), '; ') 
     FROM RankedUsers 
     WHERE BadgeCount > 100 
     AND RankByBadges <= 20) as TopBadgeHolders,
    (SELECT STRING_AGG(CONCAT(TagName, ':', Count), ' | ') 
     FROM TagStats 
     WHERE TagPopularity IN ('Trending', 'Popular') 
     AND RankByCount <= 50) as PopularTags,
    (SELECT STRING_AGG(CONCAT(VoteType, ':', COUNT(*)), ' | ') 
     FROM ComplexVoting 
     WHERE VoteType IN ('Upvote', 'Downvote')
     GROUP BY VoteType) as VoteTypeDistribution,
    (SELECT COUNT(*) 
     FROM Posts p 
     JOIN Posts p2 ON p.ParentId = p2.Id 
     WHERE p.PostTypeId = 2 
     AND EXISTS (SELECT 1 FROM Users u WHERE u.Id = p.OwnerUserId AND u.Reputation < 1000)) as LowRepAnswers,
    (SELECT STRING_AGG(CONCAT('Q', PostId, ':', Title), ' | ') 
     FROM (
        SELECT p.Id as PostId, p.Title
        FROM Posts p
        WHERE PostTypeId = 1
        AND EXISTS (SELECT 1 FROM Posts p2 WHERE p2.ParentId = p.Id)
        AND EXISTS (SELECT 1 FROM Posts p3 WHERE p3.ParentId = p.Id AND p3.Score > 0)
        AND Score < 0
        ORDER BY CreationDate DESC LIMIT 10
     ) as RecentLowScoreQuestions) as LowScoreQuestions,
    (SELECT COUNT(*) 
     FROM (
        SELECT OwnerUserId, COUNT(*) as PostsCount
        FROM Posts 
        WHERE PostTypeId = 1 
        AND Score > 100
        GROUP BY OwnerUserId
        HAVING COUNT(*) > 50
     ) as HighlyVotedQuestionAuthors) as TopQuestionAuthors,
    (SELECT AVG(ABS(Score)) 
     FROM Posts 
     WHERE PostTypeId = 1 
     AND Score < 0) as AvgNegativeQuestionScore
FROM RankedUsers ru
FULL OUTER JOIN PostAnalysis pa ON ru.UserId = pa.OwnerUserId
FULL OUTER JOIN TagStats ts ON ts.Count > 100
FULL OUTER JOIN ComplexVoting cv ON cv.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
WHERE (ru.UserId IS NOT NULL OR pa.PostId IS NOT NULL OR ts.TagName IS NOT NULL OR cv.VoteId IS NOT NULL)

UNION ALL

SELECT 
    'Advanced Metrics Report' as ReportName,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT ru.UserId) as DistinctUsers,
    COUNT(DISTINCT pa.PostId) as DistinctPosts,
    COUNT(DISTINCT ts.TagName) as DistinctTags,
    COUNT(DISTINCT cv.VoteId) as TotalVotes,
    COUNT(DISTINCT CASE WHEN pa.PostType = 'Question' THEN pa.PostId END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN pa.PostType = 'Answer' THEN pa.PostId END) as AnswerCount,
    AVG(ru.Reputation) as AvgUserReputation,
    AVG(pa.Score) as AvgPostScore,
    AVG(cv.PostScore) as AvgVoteScore,
    MAX(ru.ViewCount) as MaxUserViews,
    SUM(pa.ViewCount) as TotalPostViews,
    STRING_AGG(CONCAT(pa.PostType, ':', COUNT(*)), ' | ') as PostTypeDistribution,
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.PostTypeId = 1 
     AND p.CreationDate >= DATEADD(MONTH, -6, GETDATE())) as RecentQuestions,
    (SELECT COUNT(DISTINCT OwnerUserId) 
     FROM Posts 
     WHERE PostTypeId = 1 
     AND Score > 50) as HighScoreQuestions,
    (SELECT COUNT(DISTINCT VoteTypeId) 
     FROM Votes 
     WHERE CreationDate >= DATEADD(YEAR, -1, GETDATE())) as VoteTypesUsed,
    (SELECT AVG(GrowthRate) 
     FROM TagStats 
     WHERE GrowthRate IS NOT NULL) as AvgTagGrowth,
    COUNT(DISTINCT CASE WHEN pa.VoteCategory = 'HighlyVoted' THEN pa.PostId END) as HighlyVotedPosts,
    COUNT(DISTINCT CASE WHEN pa.Popularity = 'Popular' THEN pa.PostId END) as PopularPosts,
    COUNT(*) as TotalRows
FROM RankedUsers ru
FULL OUTER JOIN PostAnalysis pa ON ru.UserId = pa.OwnerUserId
FULL OUTER JOIN TagStats ts ON ts.Count > 100
FULL OUTER JOIN ComplexVoting cv ON cv.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
WHERE ru.UserId IS NOT NULL OR pa.PostId IS NOT NULL OR ts.TagName IS NOT NULL OR cv.VoteId IS NOT NULL

HAVING COUNT(*) > 0
ORDER BY TotalRecords DESC;