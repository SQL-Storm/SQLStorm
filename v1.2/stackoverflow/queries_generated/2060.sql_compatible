WITH PoRankedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId AS QuestionOwnerId,
        q.Score AS stats_FinalQuestionScore,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY q.Id
            ORDER BY a.Score DESC, a.CreationDate DESC
        ) AS rn
    FROM posts q
    JOIN posts a
        ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
      AND a.PostTypeId = 2
),
TopAnswers AS (
    SELECT *
    FROM PoRankedAnswers
    WHERE rn = 1
)
SELECT
    QuestionId,
    Title,
    QuestionOwnerId,
    stats_FinalQuestionScore,
    AnswerId,
    AnswerOwnerId,
    AnswerScore,
    AnswerCreationDate
FROM TopAnswers;