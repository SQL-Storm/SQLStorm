-- {"query": "7283.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2444} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysSinceCreation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
AnswerStats AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        DATEDIFF(day, q.CreationDate, a.CreationDate) AS DaysToAnswer,
        CASE 
            WHEN a.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) THEN 'AboveAvg'
            ELSE 'BelowAvg'
        END AS AnswerScoreCategory
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        STRING_AGG(CAST(b.Name AS VARCHAR(50)), ', ') AS BadgeList,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationTier,
        DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate, u.CreationDate
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id AS PostId,
        ps.PostTypeId,
        ps.ParentId,
        ps.OwnerUserId,
        ps.Score,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        ps.PostType,
        ps.ScoreCategory,
        ps.DaysSinceCreation,
        ps.UserPostRank,
        ps.TotalUserPosts,
        ps.AvgUserScore,
        ps.GlobalScoreRank,
        CASE 
            WHEN ps.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'NoAnswers'
        END AS HasAnswers,
        CASE 
            WHEN ps.CommentCount > 0 THEN 'HasComments'
            ELSE 'NoComments'
        END AS HasComments,
        CASE 
            WHEN ps.FavoriteCount > 0 THEN 'HasFavorites'
            ELSE 'NoFavorites'
        END AS HasFavorites,
        COALESCE(
            (SELECT TOP 1 a.AnswerScore 
             FROM AnswerStats a 
             WHERE a.QuestionId = ps.Id 
             ORDER BY a.AnswerScore DESC), 
            0
        ) AS BestAnswerScore,
        COALESCE(
            (SELECT TOP 1 a.AnswerDate 
             FROM AnswerStats a 
             WHERE a.QuestionId = ps.Id 
             ORDER BY a.AnswerDate ASC), 
            ps.CreationDate
        ) AS FirstAnswerDate,
        COALESCE(
            (SELECT TOP 1 a.AnswerDate 
             FROM AnswerStats a 
             WHERE a.QuestionId = ps.Id 
             ORDER BY a.AnswerDate DESC), 
            ps.CreationDate
        ) AS LatestAnswerDate
    FROM PostStats ps
),
FinalAnalysis AS (
    SELECT 
        cpa.PostId,
        cpa.PostTypeId,
        cpa.ParentId,
        cpa.OwnerUserId,
        cpa.Score,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.CreationDate,
        cpa.LastActivityDate,
        cpa.Title,
        cpa.Tags,
        cpa.PostType,
        cpa.ScoreCategory,
        cpa.DaysSinceCreation,
        cpa.UserPostRank,
        cpa.TotalUserPosts,
        cpa.AvgUserScore,
        cpa.GlobalScoreRank,
        cpa.HasAnswers,
        cpa.HasComments,
        cpa.HasFavorites,
        cpa.BestAnswerScore,
        DATEDIFF(day, cpa.CreationDate, cpa.FirstAnswerDate) AS TimeToFirstAnswer,
        DATEDIFF(day, cpa.FirstAnswerDate, cpa.LatestAnswerDate) AS TimeBetweenAnswers,
        DATEDIFF(day, cpa.CreationDate, cpa.LatestAnswerDate) AS TimeToLatestAnswer,
        CASE 
            WHEN cpa.TimeToFirstAnswer > 0 AND cpa.TimeToFirstAnswer <= 1 THEN 'QuickResponse'
            WHEN cpa.TimeToFirstAnswer > 1 AND cpa.TimeToFirstAnswer <= 7 THEN 'ModerateResponse'
            ELSE 'SlowResponse'
        END AS ResponseSpeed,
        CASE 
            WHEN cpa.Score > 10 AND cpa.AnswerCount > 0 THEN 'Engaging'
            WHEN cpa.Score > 5 AND cpa.AnswerCount > 1 THEN 'Engaging'
            ELSE 'LowEngagement'
        END AS EngagementLevel,
        ROW_NUMBER() OVER (ORDER BY cpa.Score DESC) AS ScoreRank,
        DENSE_RANK() OVER (PARTITION BY cpa.OwnerUserId ORDER BY cpa.Score DESC) AS OwnerScoreRank,
        PERCENT_RANK() OVER (ORDER BY cpa.Score) AS ScorePercentile,
        NTILE(10) OVER (ORDER BY cpa.Score) AS ScoreDecile,
        REPLICATE('=', 
            CAST(ROUND(100.0 * (cpa.Score - (SELECT MIN(Score) FROM ComplexPostAnalysis)) / 
                    NULLIF((SELECT MAX(Score) FROM ComplexPostAnalysis) - (SELECT MIN(Score) FROM ComplexPostAnalysis), 0), 0) AS INT)
        ) AS ScoreBar,
        COALESCE(
            (SELECT TOP 1 ua.DisplayName 
             FROM UserActivityStats ua 
             WHERE ua.UserId = cpa.OwnerUserId), 
            'Unknown'
        ) AS OwnerDisplayName,
        COALESCE(
            (SELECT TOP 1 ua.Reputation 
             FROM UserActivityStats ua 
             WHERE ua.UserId = cpa.OwnerUserId), 
            0
        ) AS OwnerReputation,
        COALESCE(
            (SELECT TOP 1 ua.TotalPosts 
             FROM UserActivityStats ua 
             WHERE ua.UserId = cpa.OwnerUserId), 
            0
        ) AS OwnerTotalPosts,
        CASE 
            WHEN cpa.AnswerCount > 0 AND cpa.CommentCount > 0 THEN 'Active'
            WHEN cpa.AnswerCount > 0 OR cpa.CommentCount > 0 THEN 'PartiallyActive'
            ELSE 'Inactive'
        END AS ActivityLevel
    FROM ComplexPostAnalysis cpa
)
SELECT 
    fa.PostId,
    fa.PostTypeId,
    fa.ParentId,
    fa.OwnerUserId,
    fa.Score,
    fa.AnswerCount,
    fa.CommentCount,
    fa.FavoriteCount,
    fa.CreationDate,
    fa.LastActivityDate,
    fa.Title,
    fa.Tags,
    fa.PostType,
    fa.ScoreCategory,
    fa.DaysSinceCreation,
    fa.UserPostRank,
    fa.TotalUserPosts,
    fa.AvgUserScore,
    fa.GlobalScoreRank,
    fa.HasAnswers,
    fa.HasComments,
    fa.HasFavorites,
    fa.BestAnswerScore,
    fa.TimeToFirstAnswer,
    fa.TimeBetweenAnswers,
    fa.TimeToLatestAnswer,
    fa.ResponseSpeed,
    fa.EngagementLevel,
    fa.ScoreRank,
    fa.OwnerScoreRank,
    fa.ScorePercentile,
    fa.ScoreDecile,
    fa.ScoreBar,
    fa.OwnerDisplayName,
    fa.OwnerReputation,
    fa.OwnerTotalPosts,
    fa.ActivityLevel,
    CASE 
        WHEN fa.Score > 100 AND fa.OwnerReputation > 1000 THEN 'HighValuePost'
        WHEN fa.Score > 50 AND fa.OwnerReputation > 500 THEN 'MediumValuePost'
        ELSE 'LowValuePost'
    END AS PostValueCategory,
    CASE 
        WHEN fa.GlobalScoreRank <= 10 THEN 'Top10'
        WHEN fa.GlobalScoreRank <= 100 THEN 'Top100'
        WHEN fa.GlobalScoreRank <= 1000 THEN 'Top1000'
        ELSE 'BelowTop1000'
    END AS RankingTier,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= DATEADD(month, -1, GETDATE())) AS RecentQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND CreationDate >= DATEADD(month, -1, GETDATE())) AS RecentAnswers,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= DATEADD(month, -1, GETDATE())) AS RecentAvgQuestionScore,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2 AND CreationDate >= DATEADD(month, -1, GETDATE())) AS RecentAvgAnswerScore,
    CASE 
        WHEN EXISTS(SELECT 1 FROM Votes v WHERE v.PostId = fa.PostId AND v.VoteTypeId = 2) THEN 'Upvoted'
        WHEN EXISTS(SELECT 1 FROM Votes v WHERE v.PostId = fa.PostId AND v.VoteTypeId = 3) THEN 'Downvoted'
        ELSE 'NoVotes'
    END AS VoteStatus,
    '---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---' AS SeparatorLine
FROM FinalAnalysis fa
WHERE fa.PostType = 'Question'
  AND fa.DaysSinceCreation <= 365
  AND fa.Score >= 0
  AND fa.OwnerUserId IS NOT NULL
  AND (fa.AnswerCount > 0 OR fa.CommentCount > 0)
ORDER BY fa.Score DESC, fa.GlobalScoreRank ASC, fa.CreationDate DESC
OFFSET 0 ROWS
FETCH NEXT 5000 ROWS ONLY;