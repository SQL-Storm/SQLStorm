-- {"query": "7909.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1844} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        COALESCE(p.Body, '') AS Body,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysActive,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDescription,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'ZeroOrNegative'
        END AS ScoreCategory,
        CASE 
            WHEN p.AnswerCount > 10 THEN 'ManyAnswers'
            WHEN p.AnswerCount > 5 THEN 'SomeAnswers'
            WHEN p.AnswerCount > 0 THEN 'FewAnswers'
            ELSE 'NoAnswers'
        END AS AnswerDensity,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS TypeScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) AS UserAgeDays,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END) AS Questions,
        COUNT(CASE WHEN ps.PostTypeId = 2 THEN 1 END) AS Answers,
        SUM(ps.Score) AS TotalScore,
        MAX(ps.Score) AS MaxScore,
        AVG(ps.Score) AS AvgScore,
        AVG(ps.ViewCount) AS AvgViews,
        STRING_AGG(ps.Title, ', ') AS PostTitles
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'VeryPopular'
            WHEN t.Count > 500 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Rare'
        END AS PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS PopularityRank
    FROM Tags t
    WHERE t.Count > 0
),
PostWithDetails AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.PostTypeDescription,
        ps.ScoreCategory,
        ps.AnswerDensity,
        ps.UserPostRank,
        ps.GlobalScoreRank,
        ps.TypeScoreRank,
        ps.ViewRank,
        ps.DaysActive,
        ps.Title,
        ps.Tags,
        ps.Body,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        u.Views AS OwnerViews,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = ps.PostTypeId) THEN 'AboveAverage'
            ELSE 'BelowAverage'
        END AS ScorePerformance,
        CAST(ps.ViewCount AS FLOAT) / NULLIF(ps.AnswerCount + 1, 0) AS ViewsPerAnswer,
        DATEDIFF(day, ps.CreationDate, ps.LastActivityDate) AS AgeInDays,
        CASE
            WHEN ps.AnswerCount > 0 THEN ps.Score * 1.0 / ps.AnswerCount
            ELSE NULL 
        END AS ScorePerAnswer,
        COALESCE(CAST(ps.AnswerCount AS FLOAT) / NULLIF(ps.ViewCount, 0) * 100, 0) AS AnswerRate,
        CASE 
            WHEN ps.AnswerCount >= 1 AND ps.Score >= 10 THEN 'HighValue'
            WHEN ps.AnswerCount >= 1 AND ps.Score >= 1 THEN 'MediumValue'
            ELSE 'LowValue'
        END AS ValueLevel
    FROM PostStats ps
    LEFT JOIN Users u ON ps.OwnerUserId = u.Id
),
ComplexMetrics AS (
    SELECT 
        pwd.*,
        (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE PostId = pwd.Id AND VoteTypeId IN (2, 3)) AS VoteCount,
        COALESCE((SELECT COUNT(*) FROM Comments WHERE PostId = pwd.Id), 0) AS CommentCountReal,
        (CASE WHEN pwd.PostTypeDescription = 'Question' THEN 'Q' ELSE 'A' END + '-' + 
         LEFT(pwd.Title, 20) + '-' + 
         RIGHT(pwd.Id, 6)) AS Identifier,
        (SELECT TOP 1 Name FROM Badges WHERE UserId = pwd.OwnerUserId AND 
         (Name LIKE '%Answer%' OR Name LIKE '%Question%') 
         ORDER BY Date DESC) AS RecentBadge,
        (SELECT COUNT(*) FROM Votes WHERE UserId = pwd.OwnerUserId AND VoteTypeId IN (2, 3)) AS UserVoteCount,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = pwd.OwnerUserId AND PostTypeId = 1) AS UserQuestions,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = pwd.OwnerUserId AND PostTypeId = 2) AS UserAnswers,
        (SELECT COUNT(*) FROM PostLinks WHERE PostId = pwd.Id) AS LinkCount,
        (SELECT TOP 1 Text FROM Comments WHERE PostId = pwd.Id ORDER BY CreationDate DESC) AS LatestComment,
        (SELECT TOP 1 PostHistoryTypeId FROM PostHistory WHERE PostId = pwd.Id AND PostHistoryTypeId IN (10, 11, 13, 12) ORDER BY CreationDate DESC) AS RecentPostAction
    FROM PostWithDetails pwd
)
SELECT 
    cm.Id,
    cm.Title,
    cm.OwnerDisplayName,
    cm.OwnerReputation,
    cm.Score,
    cm.ViewCount,
    cm.AnswerCount,
    cm.CommentCountReal,
    cm.ScoreCategory,
    cm.AnswerDensity,
    cm.ValueLevel,
    cm.ScorePerformance,
    cm.ViewsPerAnswer,
    cm.AnswerRate,
    cm.AgeInDays,
    cm.ScorePerAnswer,
    cm.UserPostRank,
    cm.GlobalScoreRank,
    cm.TypeScoreRank,
    cm.ViewRank,
    cm.Identifier,
    cm.RecentBadge,
    cm.UserVoteCount,
    cm.UserQuestions,
    cm.UserAnswers,
    cm.LinkCount,
    cm.LatestComment,
    cm.RecentPostAction,
    CASE 
        WHEN cm.Score > 100 AND cm.ViewCount > 1000 AND cm.AnswerCount > 3 THEN 'ElitePost'
        WHEN cm.Score > 50 AND cm.ViewCount > 500 AND cm.AnswerCount >= 1 THEN 'StrongPost'
        WHEN cm.Score > 0 AND cm.ViewCount > 100 THEN 'NotablePost'
        ELSE 'RegularPost'
    END AS PostStatus,
    ROW_NUMBER() OVER (ORDER BY cm.Score DESC, cm.ViewCount DESC) AS FinalRank,
    RANK() OVER (PARTITION BY cm.PostTypeDescription ORDER BY cm.Score DESC) AS TypeRank,
    DENSE_RANK() OVER (ORDER BY cm.OwnerReputation DESC) AS ReputationRank,
    COUNT(*) OVER () AS TotalPosts
FROM ComplexMetrics cm
WHERE cm.Score > 0 
    AND cm.ViewCount > 0
    AND cm.AnswerCount >= 0
    AND cm.Title IS NOT NULL
    AND cm.OwnerDisplayName IS NOT NULL
    AND cm.GlobalScoreRank <= 50000
ORDER BY cm.Score DESC, cm.ViewCount DESC, cm.CreationDate DESC
OFFSET 100 ROWS
FETCH NEXT 1000 ROWS ONLY;