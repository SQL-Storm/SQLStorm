WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        u.DisplayName AS OwnerName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        (
            SELECT AVG(s.Score) AS MeanNonNullScore
            FROM (
                SELECT s.Score
                FROM Posts s
                WHERE s.ParentId = p.Id
                  AND s.Score IS NOT NULL
            ) AS s
        ) AS MeanNonNullScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
)
SELECT
    QuestionId,
    Title,
    OwnerName,
    Score,
    ViewCount,
    CreationDate,
    MeanNonNullScore
FROM RankedQuestions
GROUP BY
    QuestionId,
    Title,
    OwnerName,
    Score,
    ViewCount,
    CreationDate,
    MeanNonNullScore;