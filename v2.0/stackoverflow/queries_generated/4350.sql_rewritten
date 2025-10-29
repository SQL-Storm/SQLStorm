-- {"query": "4350.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1079} 
WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionSequence,
        COUNT(a.Id) OVER (PARTITION BY p.Id) AS AnswerCountForQuestion,
        MAX(a.Score) OVER (PARTITION BY p.Id) AS MaxAnswerScoreForQuestion
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= '2020-01-01'
      AND p.Score > 10
),
UserActivity AS (
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS TotalEditedPosts,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN 1 ELSE 0 END) AS TotalBodyEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5)
    GROUP BY ph.UserId
),
CommentSentiment AS (
    SELECT
        c.PostId,
        AVG(CASE
                WHEN c.Score > 0 THEN 1.0
                WHEN c.Score < 0 THEN -1.0
                ELSE 0.0
            END) AS AverageCommentScore,
        COUNT(c.Id) AS TotalComments,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%great%' OR LOWER(c.Text) LIKE '%awesome%' THEN 1 ELSE 0 END) AS PositiveComments,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%bad%' OR LOWER(c.Text) LIKE '%terrible%' THEN 1 ELSE 0 END) AS NegativeComments
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    rq.QuestionId,
    rq.QuestionTitle,
    rq.OwnerDisplayName,
    rq.QuestionCreationDate,
    rq.QuestionScore,
    rq.QuestionViewCount,
    rq.AnswerCountForQuestion,
    rq.MaxAnswerScoreForQuestion,
    CASE
        WHEN rq.QuestionSequence <= 5 THEN 'Top 5 Most Recent'
        WHEN rq.QuestionSequence <= 20 THEN '20 Most Recent'
        ELSE 'Other'
    END AS UserQuestionRank,
    ua.TotalEditedPosts,
    ua.BodyEdits,
    cs.AverageCommentScore,
    cs.PositiveComments,
    cs.NegativeComments,
    CASE
        WHEN COALESCE(rq.OwnerUserId, -1) = -1 THEN 'Community Owned'
        WHEN rq.QuestionScore > 500 THEN 'High Score'
        WHEN rq.QuestionViewCount > 10000 THEN 'High Views'
        ELSE 'Standard'
    END AS QuestionCategorization,
    SUBSTRING(rq.QuestionTitle FROM 1 FOR 10) AS TitlePrefix
FROM RankedQuestions rq
LEFT JOIN UserActivity ua ON rq.OwnerUserId = ua.UserId
LEFT JOIN CommentSentiment cs ON rq.QuestionId = cs.PostId
WHERE (ua.TotalEditedPosts IS NULL OR ua.TotalEditedPosts < 10)
UNION ALL
SELECT
    p.Id,
    p.Title,
    u.DisplayName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    NULL AS MaxAnswerScoreForQuestion,
    'Answer Post' AS UserQuestionRank,
    NULL AS TotalEditedPosts,
    NULL AS BodyEdits,
    NULL AS AverageCommentScore,
    NULL AS PositiveComments,
    NULL AS NegativeComments,
    'Answer Post' AS QuestionCategorization,
    SUBSTRING(p.Title FROM 1 FOR 10) AS TitlePrefix
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 2
  AND p.CreationDate >= '2020-01-01'
  AND p.Score > 5
ORDER BY QuestionCreationDate DESC, QuestionScore DESC;