-- {"query": "4856.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1589} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS rn_asc,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(CAST(p.ViewCount AS FLOAT)) AS AvgViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 5
),
PostCommentScores AS (
    SELECT
        c.PostId,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(c.Id) AS TotalComments
    FROM Comments AS c
    GROUP BY c.PostId
)
SELECT
    rp_q.PostId,
    rp_q.PostTypeName AS QuestionType,
    rp_q.PostScore AS QuestionScore,
    rp_q.PostViewCount AS QuestionViews,
    rp_q.AnswerCount AS QuestionAnswerCount,
    rp_q.FavoriteCount AS QuestionFavorites,
    pcs_q.TotalCommentScore AS QuestionCommentScore,
    pcs_q.TotalComments AS QuestionTotalComments,
    rp_a.PostId AS AnswerId,
    rp_a.PostTypeName AS AnswerType,
    rp_a.PostScore AS AnswerScore,
    rp_a.PostViewCount AS AnswerViews,
    pcs_a.TotalCommentScore AS AnswerCommentScore,
    pcs_a.TotalComments AS AnswerTotalComments,
    u.UserDisplayName AS QuestionOwnerDisplayName,
    u.TotalPosts AS QuestionOwnerTotalPosts,
    u.TotalScore AS QuestionOwnerTotalScore,
    u.AvgViews AS QuestionOwnerAvgViews,
    rp_q.NextScore AS NextQuestionScore,
    rp_q.PreviousScore AS PreviousQuestionScore,
    CASE
        WHEN rp_q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp_q.PostScore > 100 THEN 'High Score'
        WHEN rp_q.AnswerCount > 10 THEN 'Popular'
        ELSE 'Standard'
    END AS QuestionStatus,
    CASE
        WHEN rp_a.PostScore > 50 THEN 'Highly Rated Answer'
        WHEN rp_a.CommentCount > 5 THEN 'Discussed Answer'
        ELSE 'Regular Answer'
    END AS AnswerQualityCategory,
    COALESCE(rp_q.PostCreationDate, rp_a.PostCreationDate) AS EarliestActivityDate,
    'Post Performance Benchmark' AS BenchmarkType
FROM RankedPosts AS rp_q
LEFT JOIN RankedPosts AS rp_a ON rp_q.Id = rp_a.ParentId AND rp_a.PostTypeId = 2 -- Assuming PostTypeId 2 is Answer
LEFT JOIN Users AS u ON rp_q.OwnerUserId = u.Id
LEFT JOIN PostCommentScores AS pcs_q ON rp_q.Id = pcs_q.PostId
LEFT JOIN PostCommentScores AS pcs_a ON rp_a.Id = pcs_a.PostId
WHERE rp_q.PostTypeId = 1 -- Assuming PostTypeId 1 is Question
  AND rp_q.rn_desc <= 100 -- Top 100 recent questions
  AND (rp_q.PostScore > 0 OR rp_q.AnswerCount > 0)
  AND rp_a.Id IS NOT NULL -- Only include questions with at least one answer
  AND rp_q.PostScore <> rp_q.PreviousScore
  AND rp_q.PostScore <> rp_q.NextScore
UNION
SELECT
    rp_q.PostId,
    rp_q.PostTypeName AS QuestionType,
    rp_q.PostScore AS QuestionScore,
    rp_q.PostViewCount AS QuestionViews,
    rp_q.AnswerCount AS QuestionAnswerCount,
    rp_q.FavoriteCount AS QuestionFavorites,
    pcs_q.TotalCommentScore AS QuestionCommentScore,
    pcs_q.TotalComments AS QuestionTotalComments,
    NULL AS AnswerId,
    NULL AS AnswerType,
    NULL AS AnswerScore,
    NULL AS AnswerViews,
    NULL AS AnswerCommentScore,
    NULL AS AnswerTotalComments,
    u.UserDisplayName AS QuestionOwnerDisplayName,
    u.TotalPosts AS QuestionOwnerTotalPosts,
    u.TotalScore AS QuestionOwnerTotalScore,
    u.AvgViews AS QuestionOwnerAvgViews,
    rp_q.NextScore AS NextQuestionScore,
    rp_q.PreviousScore AS PreviousQuestionScore,
    CASE
        WHEN rp_q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp_q.PostScore > 100 THEN 'High Score'
        WHEN rp_q.AnswerCount > 10 THEN 'Popular'
        ELSE 'Standard'
    END AS QuestionStatus,
    NULL AS AnswerQualityCategory,
    rp_q.PostCreationDate AS EarliestActivityDate,
    'Post Performance Benchmark' AS BenchmarkType
FROM RankedPosts AS rp_q
LEFT JOIN Users AS u ON rp_q.OwnerUserId = u.Id
LEFT JOIN PostCommentScores AS pcs_q ON rp_q.Id = pcs_q.PostId
WHERE rp_q.PostTypeId = 1 -- Assuming PostTypeId 1 is Question
  AND rp_q.rn_desc <= 100 -- Top 100 recent questions
  AND (rp_q.PostScore > 0 OR rp_q.AnswerCount > 0)
  AND rp_q.Id NOT IN (SELECT DISTINCT ParentId FROM Posts WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL) -- Questions without answers
  AND rp_q.PostScore <> rp_q.PreviousScore
  AND rp_q.PostScore <> rp_q.NextScore
ORDER BY EarliestActivityDate DESC;