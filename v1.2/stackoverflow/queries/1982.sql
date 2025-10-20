WITH QuestionAnswerStats AS (
    SELECT 
        Q.Id AS QuestionId,
        Q.Title,
        Q.CreationDate,
        Q.ViewCount,
        Q.Score AS QuestionScore,
        (
            SELECT COUNT(DISTINCT A.OwnerUserId)
            FROM Posts A
            WHERE A.PostTypeId = 2 
              AND A.ParentId = Q.Id
              AND A.OwnerUserId IS NOT NULL
              AND A.Score > 0
        ) AS DistinctAnswerersQuality,
        COALESCE(Q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        U.Id AS UserId,
        U.DisplayName
    FROM Posts Q
    LEFT JOIN Users U ON U.Id = Q.OwnerUserId
    WHERE Q.PostTypeId = 1
)
SELECT
    QuestionId,
    Title,
    CreationDate,
    ViewCount,
    QuestionScore,
    DistinctAnswerersQuality,
    AcceptedAnswerId,
    UserId,
    DisplayName
FROM QuestionAnswerStats
GROUP BY
    QuestionId,
    Title,
    CreationDate,
    ViewCount,
    QuestionScore,
    DistinctAnswerersQuality,
    AcceptedAnswerId,
    UserId,
    DisplayName;