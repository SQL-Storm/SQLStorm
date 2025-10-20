WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS AnswerRank,
        COUNT(c.Id) AS CommentsCount,
        STRING_AGG(DISTINCT COALESCE(b.Name, 'NoBadge') , ',' ) AS BadgesHumanString
    FROM Posts a
    LEFT JOIN Comments c ON c.PostId = a.Id
    LEFT JOIN (
        SELECT u.Id, ba.Name
        FROM Users u
        LEFT JOIN Badges ba ON ba.UserId = u.Id AND ba.Class = 1
    ) b ON a.OwnerUserId = b.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.Score, a.CreationDate, b.Name
)
SELECT *
FROM RankedAnswers;