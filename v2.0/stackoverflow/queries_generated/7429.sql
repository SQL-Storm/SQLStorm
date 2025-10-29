-- {"query": "7429.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2677} 
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.LastActivityDate,
        p.ParentId,
        p.AcceptedAnswerId,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS ActivityScore,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostTypeDesc,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        NTILE(100) OVER (ORDER BY p.Score) AS ScorePercentile,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Negative'
        END AS ScoreCategory
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01' AND p.CreationDate < '2023-01-01'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ps.PostId) AS TotalPosts,
        AVG(ps.Score) AS AvgPostScore,
        MAX(ps.Score) AS MaxPostScore,
        SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(ps.AnswerCount) AS TotalAnswers,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Expert'
            WHEN u.Reputation > 1000 THEN 'Intermediate'
            WHEN u.Reputation > 100 THEN 'Beginner'
            ELSE 'Newbie'
        END AS UserLevel,
        DATEDIFF(CURDATE(), u.CreationDate) AS DaysSinceJoining
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(SUBSTRING(t.TagName, 1, 5), 'UNKNOWN') AS TagPrefix,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END AS PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 10
),
QuestionAnalysis AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.ActivityScore,
        ps.ScoreCategory,
        ps.ScoreRank,
        ps.ScorePercentile,
        ps.RecentPostRank,
        ps.PostTypeDesc,
        ps.PrevScore,
        ps.ParentId,
        ps.AcceptedAnswerId,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.PostId = ps.PostId 
             AND c.CreationDate BETWEEN ps.CreationDate AND ps.CreationDate + INTERVAL 30 DAY
            ), 0
        ) AS CommentsIn30Days,
        CASE 
            WHEN ps.AnswerCount > 0 THEN (ps.Score + 1) / (ps.AnswerCount + 1)
            ELSE ps.Score
        END AS ScorePerAnswer,
        CASE 
            WHEN ps.LastActivityDate > ps.CreationDate + INTERVAL 7 DAY THEN 'Active'
            ELSE 'Inactive'
        END AS ActivityStatus,
        LAG(ps.Score, 1, ps.Score) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) AS PriorScore,
        ps.Score - LAG(ps.Score, 1, ps.Score) OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) AS ScoreChange,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAvg'
            ELSE 'BelowAvg'
        END AS ScoreVsAvg
    FROM PostStats ps
    WHERE ps.PostTypeId = 1
),
AnswerAnalysis AS (
    SELECT 
        ps.PostId AS AnswerId,
        ps.ParentId AS QuestionId,
        ps.Score,
        ps.CreationDate AS AnswerDate,
        ps.OwnerUserId AS AnswererId,
        ps.ActivityScore,
        ps.ScoreCategory,
        ps.ScoreRank,
        ps.ScorePercentile,
        ps.RecentPostRank,
        ps.PostTypeDesc,
        ps.PrevScore,
        ps.AcceptedAnswerId,
        ps.Tags,
        ps.Title,
        CASE 
            WHEN ps.Score > 50 THEN 'Valuable'
            WHEN ps.Score > 10 THEN 'Useful'
            ELSE 'Basic'
        END AS QualityLevel,
        DENSE_RANK() OVER (PARTITION BY ps.ParentId ORDER BY ps.Score DESC) AS AnswerRank,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId = 3) AS Downvotes
    FROM PostStats ps
    WHERE ps.PostTypeId = 2
),
UserPerformance AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.Views,
        us.UpVotes,
        us.DownVotes,
        us.TotalPosts,
        us.AvgPostScore,
        us.MaxPostScore,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalAnswers,
        us.UserLevel,
        us.DaysSinceJoining,
        CASE 
            WHEN us.TotalPosts > 0 THEN us.AnswerCount * 100.0 / us.TotalPosts
            ELSE 0
        END AS AnswerPercentage,
        CASE 
            WHEN us.Reputation > 0 THEN us.UpVotes * 100.0 / us.Reputation
            ELSE 0
        END AS UpvoteRatio,
        CASE 
            WHEN us.TotalPosts > 0 THEN (us.QuestionCount + us.AnswerCount * 0.5) / us.TotalPosts
            ELSE 0
        END AS ContributionScore,
        NTILE(10) OVER (ORDER BY us.Reputation DESC) AS RepQuartile,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC) AS RankByRep,
        ROW_NUMBER() OVER (ORDER BY us.AvgPostScore DESC) AS RankByAvgScore,
        ROW_NUMBER() OVER (ORDER BY us.TotalPosts DESC) AS RankByPosts
    FROM UserStats us
    WHERE us.Reputation > 0 AND us.DaysSinceJoining > 30
),
FinalAnalysis AS (
    SELECT 
        q.PostId AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.CreationDate,
        q.OwnerUserId,
        q.ActivityScore,
        q.ActivityStatus,
        q.ScoreCategory,
        q.ScoreVsAvg,
        q.ScoreChange,
        u.DisplayName AS QuestionerName,
        u.Reputation AS QuestionerRep,
        u.UserLevel AS QuestionerLevel,
        a.AnswerId,
        a.Score AS AnswerScore,
        a.AnswerDate,
        a.AnswererId,
        a.QualityLevel,
        a.AnswerRank,
        a.Upvotes AS AnswerUpvotes,
        a.Downvotes AS AnswerDownvotes,
        COALESCE(t.TagName, 'No Tags') AS PrimaryTag,
        t.TagCount,
        CASE 
            WHEN a.AnswerScore >= 10 THEN 'Good'
            WHEN a.AnswerScore >= 5 THEN 'Fair'
            ELSE 'Poor'
        END AS AnswerQuality,
        CASE 
            WHEN a.AnswerRank = 1 THEN 'Best Answer'
            WHEN a.AnswerRank <= 3 THEN 'Top 3'
            ELSE 'Other'
        END AS AnswerPosition,
        DATEDIFF(q.CreationDate, a.AnswerDate) AS AnswerDelayDays,
        CASE 
            WHEN q.CreationDate > CURRENT_TIMESTAMP - INTERVAL 1 WEEK THEN 'Recent'
            ELSE 'Old'
        END AS QuestionAge,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC) AS QuestionRank,
        DENSE_RANK() OVER (ORDER BY q.ViewCount DESC) AS ViewRank,
        RANK() OVER (ORDER BY q.AnswerCount DESC) AS AnswerCountRank
    FROM QuestionAnalysis q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN AnswerAnalysis a ON q.PostId = a.QuestionId
    LEFT JOIN TagAnalysis t ON POSITION(CONCAT('<', t.TagName, '>') IN CONCAT('<', IFNULL(q.Tags, ''), '>')) > 0
    WHERE a.AnswerScore IS NOT NULL OR q.AnswerCount = 0
)
SELECT 
    QuestionId,
    QuestionerName,
    QuestionerRep,
    QuestionerLevel,
    Title,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    CreationDate,
    ActivityScore,
    ActivityStatus,
    ScoreCategory,
    ScoreVsAvg,
    AnswerId,
    AnswerScore,
    AnswerDate,
    AnswererId,
    QualityLevel,
    AnswerRank,
    AnswerUpvotes,
    AnswerDownvotes,
    PrimaryTag,
    TagCount,
    AnswerQuality,
    AnswerPosition,
    AnswerDelayDays,
    QuestionAge,
    QuestionRank,
    ViewRank,
    AnswerCountRank,
    CASE 
        WHEN AnswerUpvotes > AnswerDownvotes THEN 'Upvoted'
        WHEN AnswerUpvotes < AnswerDownvotes THEN 'Downvoted'
        ELSE 'Neutral'
    END AS VoteStatus,
    CASE 
        WHEN Score > 100 AND AnswerCount > 0 THEN 'HighValue'
        WHEN Score > 50 AND AnswerCount > 0 THEN 'MediumValue'
        ELSE 'LowValue'
    END AS QuestionValue,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = QuestionId 
         AND v.VoteTypeId = 5
        ), 0
    ) AS BookmarkCount,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = QuestionId
        ), 0
    ) AS CommentCountTotal,
    CASE 
        WHEN ViewCount > 1000 THEN 'Viral'
        WHEN ViewCount > 100 THEN 'Popular'
        ELSE 'Normal'
    END AS PopularityLevel,
    (SELECT AVG(ViewCount) FROM FinalAnalysis fa WHERE fa.QuestionAge = 'Recent') AS AvgRecentViews,
    (SELECT AVG(Score) FROM FinalAnalysis fa WHERE fa.QuestionAge = 'Recent') AS AvgRecentScore
FROM FinalAnalysis
WHERE QuestionId IS NOT NULL
GROUP BY 
    QuestionId, QuestionerName, QuestionerRep, QuestionerLevel, Title, Score, ViewCount, 
    AnswerCount, CommentCount, FavoriteCount, CreationDate, ActivityScore, ActivityStatus,
    ScoreCategory, ScoreVsAvg, AnswerId, AnswerScore, AnswerDate, AnswererId, QualityLevel,
    AnswerRank, AnswerUpvotes, AnswerDownvotes, PrimaryTag, TagCount, AnswerQuality,
    AnswerPosition, AnswerDelayDays, QuestionAge, QuestionRank, ViewRank, AnswerCountRank
HAVING 
    COUNT(*) >= 1
ORDER BY Score DESC, ViewCount DESC
LIMIT 1000;