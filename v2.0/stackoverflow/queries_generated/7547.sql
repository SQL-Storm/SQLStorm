-- {"query": "7547.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2608} 
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
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END AS IsClosed,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 1 
            ELSE 0 
        END AS HasAnswers,
        CASE 
            WHEN p.PostTypeId = 2 THEN (
                SELECT TOP 1 Score 
                FROM Posts p2 
                WHERE p2.ParentId = p.Id 
                ORDER BY p2.Score DESC
            ) 
            ELSE NULL 
        END AS MaxAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM Posts p
),
UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) AS TotalPosts,
        SUM(ps.Score) AS TotalScore,
        SUM(ps.ViewCount) AS TotalViews,
        AVG(ps.Score) AS AvgScore,
        MAX(ps.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 2 THEN ps.Id END) AS AnswerCount,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId IN (1,2) THEN ps.Id END) AS QuestionAnswerCount,
        MAX(CASE WHEN ps.HasAcceptedAnswer = 1 THEN 1 ELSE 0 END) AS HasAcceptedAnswers,
        COUNT(DISTINCT CASE WHEN ps.IsClosed = 1 THEN ps.Id END) AS ClosedPosts
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        SUBSTRING(t.TagName, 1, 5) AS TagPrefix,
        CASE WHEN t.Count > 1000 THEN 'Popular' 
             WHEN t.Count > 100 THEN 'Moderate' 
             ELSE 'Rare' END AS TagCategory,
        COALESCE(
            (SELECT TOP 1 p.Title 
             FROM Posts p 
             WHERE p.Tags LIKE '%' + t.TagName + '%' 
             AND p.PostTypeId = 1
             ORDER BY p.CreationDate DESC), 
            'No Recent Questions'
        ) AS RecentQuestionTitle
    FROM Tags t
),
ComplexPostAnalysis AS (
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
        ps.Title,
        ps.Tags,
        ps.HasAcceptedAnswer,
        ps.IsClosed,
        ps.HasAnswers,
        ps.MaxAnswerScore,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ViewRank,
        CASE WHEN ps.Score > (SELECT AVG(Score) FROM PostStats WHERE PostTypeId = 1) THEN 1 ELSE 0 END AS AboveAvgScore,
        CASE WHEN ps.ViewCount > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ViewCount) FROM PostStats) THEN 1 ELSE 0 END AS Above75thPercentileViews,
        CASE WHEN ps.IsClosed = 1 AND ps.Score < 0 THEN 'Poorly Closed' 
             WHEN ps.IsClosed = 1 AND ps.Score >= 0 THEN 'Well Closed'
             ELSE 'Not Closed' END AS PostClosureQuality,
        DATEDIFF('day', ps.CreationDate, ps.LastActivityDate) AS DaysSinceLastActivity,
        CASE 
            WHEN ps.AnswerCount > 0 AND ps.AnswerCount <= 5 THEN 'Few Answers'
            WHEN ps.AnswerCount > 5 AND ps.AnswerCount <= 20 THEN 'Moderate Answers' 
            WHEN ps.AnswerCount > 20 THEN 'Many Answers'
            ELSE 'No Answers' 
        END AS AnswerVolume,
        COALESCE(
            (SELECT TOP 1 v.VoteTypeId 
             FROM Votes v 
             WHERE v.PostId = ps.Id 
             AND v.VoteTypeId IN (2,3) 
             ORDER BY v.CreationDate DESC), 
            0
        ) AS RecentVoteType,
        CASE 
            WHEN ps.PostTypeId = 1 AND ps.Score > 100 THEN 'Highly Upvoted Question'
            WHEN ps.PostTypeId = 1 AND ps.Score < -10 THEN 'Highly Downvoted Question'
            WHEN ps.PostTypeId = 1 THEN 'Neutral Question'
            WHEN ps.PostTypeId = 2 AND ps.Score > 100 THEN 'Highly Upvoted Answer'
            WHEN ps.PostTypeId = 2 AND ps.Score < -10 THEN 'Highly Downvoted Answer'
            ELSE 'Neutral Answer' 
        END AS PostRating,
        CASE 
            WHEN ps.Tags LIKE '%%' AND ps.Title LIKE '%?%' THEN 1 
            ELSE 0 
        END AS QuestionFormat,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags != '' AND ps.Tags != ' ' THEN 1 
            ELSE 0 
        END AS HasTags
    FROM PostStats ps
)
SELECT 
    *
FROM (
    SELECT 
        cp.Id,
        cp.PostTypeId,
        cp.OwnerUserId,
        cp.Score,
        cp.ViewCount,
        cp.AnswerCount,
        cp.CommentCount,
        cp.FavoriteCount,
        cp.CreationDate,
        cp.LastActivityDate,
        cp.Title,
        cp.Tags,
        cp.HasAcceptedAnswer,
        cp.IsClosed,
        cp.HasAnswers,
        cp.MaxAnswerScore,
        cp.UserPostRank,
        cp.ScoreRank,
        cp.ViewRank,
        cp.AboveAvgScore,
        cp.Above75thPercentileViews,
        cp.PostClosureQuality,
        cp.DaysSinceLastActivity,
        cp.AnswerVolume,
        cp.RecentVoteType,
        cp.PostRating,
        cp.QuestionFormat,
        cp.HasTags,
        ua.Reputation,
        ua.DisplayName,
        ua.Views AS UserViews,
        ua.UpVotes,
        ua.DownVotes,
        ua.AccountId,
        ua.TotalPosts,
        ua.TotalScore,
        ua.TotalViews,
        ua.AvgScore,
        ua.LastPostDate,
        ua.QuestionCount,
        ua.AnswerCount AS UserAnswerCount,
        ua.QuestionAnswerCount,
        ua.HasAcceptedAnswers,
        ua.ClosedPosts,
        ta.TagName,
        ta.Count AS TagCount,
        ta.ExcerptPostId,
        ta.WikiPostId,
        ta.IsModeratorOnly,
        ta.IsRequired,
        ta.TagPrefix,
        ta.TagCategory,
        ta.RecentQuestionTitle,
        CASE 
            WHEN cp.PostTypeId = 1 THEN 
                CASE WHEN ua.QuestionCount > 50 THEN 'Expert' 
                     WHEN ua.QuestionCount > 10 THEN 'Intermediate' 
                     ELSE 'Beginner' END
            WHEN cp.PostTypeId = 2 THEN 
                CASE WHEN ua.AnswerCount > 100 THEN 'Expert' 
                     WHEN ua.AnswerCount > 20 THEN 'Intermediate' 
                     ELSE 'Beginner' END
            ELSE 'Unknown'
        END AS UserExpertiseLevel,
        CASE 
            WHEN cp.PostTypeId = 1 AND cp.Score > 200 THEN 'Trending Question'
            WHEN cp.PostTypeId = 1 AND cp.Score <= 200 AND cp.Score > 50 THEN 'Popular Question' 
            WHEN cp.PostTypeId = 1 THEN 'Regular Question'
            ELSE 'Other Post' 
        END AS PostPopularity,
        CASE 
            WHEN cp.PostTypeId = 1 THEN 
                CAST(cp.AnswerCount AS DECIMAL(10,2)) / CAST(NULLIF(cp.ViewCount, 0) AS DECIMAL(10,2)) * 100
            ELSE NULL 
        END AS AnswerToViewRatio,
        CASE 
            WHEN cp.PostTypeId = 1 AND cp.HasTags = 1 THEN 
                (SELECT COUNT(*) FROM STRING_SPLIT(cp.Tags, '<') WHERE TRIM(value) != '') - 1
            ELSE 0 
        END AS NumberOfTags
    FROM ComplexPostAnalysis cp
    LEFT JOIN UserActivity ua ON cp.OwnerUserId = ua.Id
    LEFT JOIN TagAnalysis ta ON cp.Tags IS NOT NULL AND ta.TagName IN (
        SELECT TRIM(value) 
        FROM STRING_SPLIT(cp.Tags, '<') 
        WHERE TRIM(value) != '' AND TRIM(value) != ' '
    )
    
    UNION ALL
    
    SELECT 
        -1 AS Id,
        99 AS PostTypeId,
        -1 AS OwnerUserId,
        -1 AS Score,
        -1 AS ViewCount,
        -1 AS AnswerCount,
        -1 AS CommentCount,
        -1 AS FavoriteCount,
        TIMESTAMP '1900-01-01' AS CreationDate,
        TIMESTAMP '1900-01-01' AS LastActivityDate,
        'Aggregate Stats' AS Title,
        'N/A' AS Tags,
        0 AS HasAcceptedAnswer,
        0 AS IsClosed,
        0 AS HasAnswers,
        -1 AS MaxAnswerScore,
        -1 AS UserPostRank,
        -1 AS ScoreRank,
        -1 AS ViewRank,
        0 AS AboveAvgScore,
        0 AS Above75thPercentileViews,
        'Aggregate' AS PostClosureQuality,
        -1 AS DaysSinceLastActivity,
        'N/A' AS AnswerVolume,
        -1 AS RecentVoteType,
        'Aggregate' AS PostRating,
        0 AS QuestionFormat,
        0 AS HasTags,
        -1 AS Reputation,
        'Aggregate Analysis' AS DisplayName,
        -1 AS UserViews,
        -1 AS UpVotes,
        -1 AS DownVotes,
        -1 AS AccountId,
        -1 AS TotalPosts,
        -1 AS TotalScore,
        -1 AS TotalViews,
        -1 AS AvgScore,
        TIMESTAMP '1900-01-01' AS LastPostDate,
        -1 AS QuestionCount,
        -1 AS UserAnswerCount,
        -1 AS QuestionAnswerCount,
        -1 AS HasAcceptedAnswers,
        -1 AS ClosedPosts,
        'Aggregate' AS TagName,
        -1 AS TagCount,
        -1 AS ExcerptPostId,
        -1 AS WikiPostId,
        0 AS IsModeratorOnly,
        0 AS IsRequired,
        'A' AS TagPrefix,
        'Aggregate' AS TagCategory,
        'N/A' AS RecentQuestionTitle,
        'Aggregate' AS UserExpertiseLevel,
        'Aggregate' AS PostPopularity,
        -1 AS AnswerToViewRatio,
        -1 AS NumberOfTags
) AS FinalResult
WHERE (FinalResult.PostTypeId = 1 AND FinalResult.Score > 50 AND FinalResult.ViewCount > 1000) 
   OR (FinalResult.PostTypeId = 2 AND FinalResult.Score > 200) 
   OR FinalResult.Id = -1
ORDER BY FinalResult.Score DESC, FinalResult.ViewCount DESC, FinalResult.CreationDate DESC
LIMIT 10000;