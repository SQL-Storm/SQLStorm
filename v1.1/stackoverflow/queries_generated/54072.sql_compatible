SELECT
    p.Id                                   AS QuestionId,
    p.Title,
    p.Tags,
    u.DisplayName                          AS Author,
    u.Reputation,
    p.AnswerCount,
    COALESCE(vk.VoteSum, 0)                AS VoteSum,
    COALESCE(ph.EditCount, 0)              AS EditCount,
    MAX(ph.LastTitleEdit)                  AS LastTitleEditDate,
    MAX(ph.LastBodyEdit)                   AS LastBodyEditDate,
    COALESCE(dl.DuplicateCount, 0)         AS DuplicateCount,
    dl.DuplicateId,
    cx.CloseReason
FROM
    Posts p
    INNER JOIN Users u
        ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            v.PostId,
            SUM(
                CASE WHEN v.VoteTypeId = 2 THEN 1
                     WHEN v.VoteTypeId = 3 THEN -1
                     ELSE 0 END
            ) AS VoteSum
        FROM Votes v
        GROUP BY v.PostId
    ) vk
        ON vk.PostId = p.Id
    LEFT JOIN (
        SELECT
            ph.PostId,
            COUNT(*)                                         AS EditCount,
            MAX(CASE WHEN ph.PostHistoryTypeId = 4
                     THEN ph.CreationDate
                     END)                                      AS LastTitleEdit,
            MAX(CASE WHEN ph.PostHistoryTypeId = 5
                     THEN ph.CreationDate
                     END)                                      AS LastBodyEdit
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4,5,6,8,9)
        GROUP BY ph.PostId
    ) ph
        ON ph.PostId = p.Id
    LEFT JOIN (
        SELECT
            pl.PostId,
            COUNT(*)                                   AS DuplicateCount,
            MAX(pl.RelatedPostId)                      AS DuplicateId
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
        GROUP BY pl.PostId
    ) dl
        ON dl.PostId = p.Id
    LEFT JOIN (
        SELECT
            ph.PostId,
            MAX(CAST(ph.Comment AS INTEGER)) AS CloseReason
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.PostId
    ) cx
        ON cx.PostId = p.Id
WHERE
    p.PostTypeId = 1
GROUP BY
    p.Id,
    p.Title,
    p.Tags,
    u.DisplayName,
    u.Reputation,
    p.AnswerCount,
    vk.VoteSum,
    ph.EditCount,
    dl.DuplicateCount,
    dl.DuplicateId,
    cx.CloseReason,
    p.Score,
    p.CreationDate
ORDER BY
    p.AnswerCount          DESC,
    p.Score                DESC,
    p.CreationDate         DESC
LIMIT 1000;