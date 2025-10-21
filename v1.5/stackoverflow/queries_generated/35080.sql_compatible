WITH TopQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.OwnerUserId,
        u.DisplayName,
        COUNT(a.Id) AS AnswerCount
    FROM
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, u.DisplayName
    HAVING
        COUNT(a.Id) > 0
),
TopQuestionsMetrics AS (
    SELECT
        tq.QuestionId,
        tq.Title,
        tq.CreationDate,
        tq.ViewCount,
        tq.Score,
        tq.OwnerUserId,
        tq.DisplayName,
        tq.AnswerCount,
        COUNT(DISTINCT c.Id) AS UniqueCommenters,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        MAX(a.Score) AS HighestAnswerScore
    FROM
        TopQuestions tq
        LEFT JOIN Comments c ON c.PostId = tq.QuestionId
        LEFT JOIN Votes v ON v.PostId = tq.QuestionId
        LEFT JOIN Posts a ON a.ParentId = tq.QuestionId AND a.PostTypeId = 2
    GROUP BY
        tq.QuestionId, tq.Title, tq.CreationDate, tq.ViewCount, tq.Score, tq.OwnerUserId, tq.DisplayName, tq.AnswerCount
),
FrequentEditors AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS EditCount
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6) -- title/body/tag edits
        AND ph.PostId IN (SELECT QuestionId FROM TopQuestions)
    GROUP BY
        ph.PostId
)
SELECT
    tqm.QuestionId,
    tqm.Title,
    tqm.CreationDate,
    tqm.ViewCount,
    tqm.Score AS QuestionScore,
    tqm.DisplayName AS QuestionAuthor,
    tqm.AnswerCount,
    tqm.UniqueCommenters,
    tqm.Upvotes,
    tqm.Downvotes,
    tqm.HighestAnswerScore,
    COALESCE(fe.EditCount, 0) AS DistinctEditors,
    (
        SELECT COUNT(DISTINCT b.Id)
        FROM Badges b
        WHERE b.UserId = tqm.OwnerUserId
        AND b.Class = 1 -- Gold badges
    ) AS GoldBadgesAuthor
FROM
    TopQuestionsMetrics tqm
    LEFT JOIN FrequentEditors fe ON tqm.QuestionId = fe.PostId
ORDER BY
    tqm.ViewCount DESC,
    tqm.Score DESC
LIMIT 50;