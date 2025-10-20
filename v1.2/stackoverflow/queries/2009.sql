WITH FilteredQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Tags,
        p.ViewCount,
        p.Score,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCountOnQuestion,
        COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Tags,
        p.ViewCount,
        p.Score
)
SELECT *
FROM FilteredQuestions;