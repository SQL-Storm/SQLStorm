-- {"query": "48003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 777} 
WITH QuestionData AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        p.CreationDate AS QuestionCreationDate,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 1 THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 5)
    WHERE p.PostTypeId = 1
    GROUP BY
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName,
        u.Reputation,
        p.CreationDate
),
AnswerData AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE NULL END) AS AcceptedAnswerCount
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
)
SELECT
    qd.QuestionId,
    qd.QuestionTitle,
    qd.QuestionScore,
    qd.QuestionViewCount,
    qd.OwnerDisplayName,
    qd.OwnerReputation,
    qd.QuestionCreationDate,
    qd.CommentCount,
    qd.TitleEdits,
    qd.BodyEdits,
    COALESCE(ad.AnswerCount, 0) AS TotalAnswers,
    COALESCE(ad.TotalAnswerScore, 0) AS TotalAnswersScore,
    COALESCE(ad.AvgAnswerScore, 0.0) AS AverageAnswerScore,
    COALESCE(ad.AcceptedAnswerCount, 0) AS NumberOfAcceptedAnswers,
    (qd.QuestionScore * 1.0 / NULLIF(qd.QuestionViewCount, 0)) AS ScorePerView,
    (qd.AnswerCount * 1.0 / NULLIF(qd.QuestionViewCount, 0)) AS AnswersPerView,
    (qd.CommentCount * 1.0 / NULLIF(qd.QuestionViewCount, 0)) AS CommentsPerView,
    (qd.TitleEdits * 1.0 / NULLIF(qd.QuestionViewCount, 0)) AS TitleEditsPerView,
    (qd.BodyEdits * 1.0 / NULLIF(qd.QuestionViewCount, 0)) AS BodyEditsPerView
FROM QuestionData qd
LEFT JOIN AnswerData ad ON qd.QuestionId = ad.QuestionId
ORDER BY
    qd.QuestionScore DESC,
    qd.QuestionViewCount DESC,
    qd.QuestionCreationDate ASC
LIMIT 1000;