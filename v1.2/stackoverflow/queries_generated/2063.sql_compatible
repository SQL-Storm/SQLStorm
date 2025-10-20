WITH RankedQuestions AS (
    SELECT 
        p.Id AS QuestionId, 
        p.Title,
        p.OwnerUserId, 
        p.Score, 
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.Id) AS rn
    FROM posts p
    WHERE p.PostTypeId = 1
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.Score
FROM RankedQuestions rq
WHERE rq.rn <= 5
ORDER BY rq.OwnerUserId, rq.Score DESC, rq.QuestionId;