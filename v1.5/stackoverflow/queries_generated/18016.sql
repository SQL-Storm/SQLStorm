-- {"query": "18016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 993} 

WITH QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        MAX(a.CreationDate) AS LastAnswerDate,
        RANK() OVER (ORDER BY COUNT(a.Id) DESC, SUM(a.Score) DESC) AS AnswerRank,
        AVG(a.Score) OVER (PARTITION BY p.Id) AS AvgAnswerScore
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title, p.CreationDate, u.DisplayName
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.OwnerDisplayName,
    qs.QuestionCreationDate,
    qs.AnswerCount,
    qs.TotalAnswerScore,
    qs.LastAnswerDate,
    qs.AvgAnswerScore,
    ca.CommentCount,
    ca.TotalCommentScore,
    ca.LastCommentDate,
    phs.EditCount,
    phs.LastEditDate,
    COALESCE(p.ViewCount, 0) AS ViewCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    CASE
        WHEN qs.AnswerRank <= 10 THEN 'Top 10 by Answers'
        WHEN qs.TotalAnswerScore > 1000 THEN 'High Score Potential'
        ELSE 'Standard'
    END AS QuestionCategory,
    DENSE_RANK() OVER (ORDER BY p.FavoriteCount DESC) AS FavoriteRank,
    ROW_NUMBER() OVER (PARTITION BY qs.OwnerDisplayName ORDER BY qs.QuestionCreationDate DESC) AS UserQuestionSequence,
    SUBSTRING(qs.Title FROM 1 FOR 20) AS TruncatedTitle,
    CASE
        WHEN qs.LastAnswerDate > qs.QuestionCreationDate + INTERVAL '1 day' THEN 'Fast Response'
        WHEN qs.LastAnswerDate IS NULL THEN 'No Answers Yet'
        ELSE 'Standard Response Time'
    END AS ResponseTimeCategory,
    CASE
        WHEN phs.LastEditDate > qs.QuestionCreationDate + INTERVAL '7 days' THEN 'Active Editing'
        ELSE 'Less Active Editing'
    END AS EditingActivity,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE pl.PostId = qs.QuestionId AND pl.LinkTypeId = 3 -- Duplicate Link
        ) THEN 'Is Duplicate'
        ELSE 'Not a Duplicate'
    END AS DuplicateStatus,
    CASE
        WHEN ca.LastCommentDate IS NOT NULL AND ca.LastCommentDate > qs.LastActivityDate THEN 'Comments after last post activity'
        ELSE 'Comments align with post activity'
    END AS CommentActivityCheck,
    CAST(qs.TotalAnswerScore AS DECIMAL(18, 2)) / NULLIF(qs.AnswerCount, 0) AS MeanAnswerScore,
    LENGTH(qs.Title) AS TitleLength
FROM QuestionStats qs
LEFT JOIN CommentAggregates ca ON qs.QuestionId = ca.PostId
LEFT JOIN PostHistorySummary phs ON qs.QuestionId = phs.PostId
LEFT JOIN Posts p ON qs.QuestionId = p.Id
WHERE qs.AnswerCount > 0
ORDER BY qs.QuestionCreationDate DESC
LIMIT 100;
