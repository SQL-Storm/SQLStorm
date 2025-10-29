-- {"query": "4677.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1601} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn_by_type,
        RANK() OVER(ORDER BY p.Score DESC) as rank_by_score,
        LAG(p.Score, 1, 0) OVER(ORDER BY p.CreationDate) as PreviousDayScore,
        SUM(p.ViewCount) OVER(ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as CumulativeViewCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATE('now', '-30 day')
      AND p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
AnswerStats AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS NumberOfAnswers,
        AVG(p.Score) AS AverageAnswerScore,
        MAX(p.CreationDate) AS LatestAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2 -- It's an Answer
      AND p.ParentId IS NOT NULL
    GROUP BY p.ParentId
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS NumberOfComments,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
UserPostEngagement AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS PostsEditedOrModified,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId END) AS PostsWithEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN ph.PostId END) AS PostsWithModerationActions
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.CreationDate >= DATE('now', '-90 day')
    GROUP BY ph.UserId
),
FinalData AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.OwnerDisplayName,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ClosedDate,
        rp.rn_by_type,
        rp.rank_by_score,
        rp.PreviousDayScore,
        rp.CumulativeViewCount,
        COALESCE(ans.NumberOfAnswers, 0) AS TotalAnswers,
        COALESCE(ans.AverageAnswerScore, 0.0) AS AvgAnswerScore,
        CASE WHEN rp.PostTypeId = 1 THEN ans.LatestAnswerDate ELSE NULL END AS QuestionLatestAnswerDate,
        COALESCE(comm.NumberOfComments, 0) AS TotalComments,
        comm.PositiveCommentCount,
        comm.LatestCommentDate,
        CASE WHEN rp.Score > 100 AND rp.ViewCount > 10000 THEN 'High Engagement'
             WHEN rp.Score < 0 THEN 'Negative Score'
             ELSE 'Standard'
        END AS EngagementCategory,
        CASE
            WHEN upe.PostsEditedOrModified IS NULL THEN 0
            ELSE upe.PostsEditedOrModified
        END AS UserEditsAndModifications,
        CASE
            WHEN upe.PostsWithEdits IS NULL THEN 0
            ELSE upe.PostsWithEdits
        END AS UserPostsWithEdits,
        CASE
            WHEN upe.PostsWithModerationActions IS NULL THEN 0
            ELSE upe.PostsWithModerationActions
        END AS UserPostsWithModeration,
        CAST(rp.Title AS TEXT) AS PostTitle,
        rp.OwnerUserId,
        CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        rp.Score * 1.5 + rp.ViewCount * 0.1 + COALESCE(ans.NumberOfAnswers, 0) * 5 AS WeightedScore,
        SUBSTRING(rp.Title, 1, 50) AS ShortTitle,
        UPPER(rp.PostTypeName) AS POSTTYPEUPPER
    FROM RankedPosts rp
    LEFT JOIN AnswerStats ans ON rp.PostId = ans.QuestionId
    LEFT JOIN CommentAggregates comm ON rp.PostId = comm.PostId
    LEFT JOIN UserPostEngagement upe ON rp.OwnerUserId = upe.UserId AND rp.OwnerUserId IS NOT NULL
)
SELECT
    fd.PostId,
    fd.PostTypeName,
    fd.OwnerDisplayName,
    fd.CreationDate,
    fd.Score,
    fd.ViewCount,
    fd.AnswerCount,
    fd.CommentCount,
    fd.FavoriteCount,
    fd.ClosedDate,
    fd.rn_by_type,
    fd.rank_by_score,
    fd.PreviousDayScore,
    fd.CumulativeViewCount,
    fd.TotalAnswers,
    fd.AvgAnswerScore,
    fd.QuestionLatestAnswerDate,
    fd.TotalComments,
    fd.PositiveCommentCount,
    fd.LatestCommentDate,
    fd.EngagementCategory,
    fd.UserEditsAndModifications,
    fd.UserPostsWithEdits,
    fd.UserPostsWithModeration,
    fd.PostTitle,
    fd.OwnerUserId,
    fd.PostStatus,
    fd.WeightedScore,
    fd.ShortTitle,
    fd.POSTTYPEUPPER,
    CASE
        WHEN fd.Score IS NULL THEN 'No Score'
        WHEN fd.Score > 0 THEN 'Positive'
        WHEN fd.Score < 0 THEN 'Negative'
        ELSE 'Zero'
    END AS ScoreSign,
    CASE
        WHEN fd.AnswerCount IS NULL THEN 'N/A'
        WHEN fd.AnswerCount > 10 THEN 'Many Answers'
        ELSE CAST(fd.AnswerCount AS VARCHAR)
    END AS AnswerCountCategory
FROM FinalData fd
WHERE fd.rn_by_type <= 50 -- Top 50 posts by creation date for each type
ORDER BY fd.PostTypeName, fd.CreationDate DESC;
