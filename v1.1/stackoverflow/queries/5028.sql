WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC, u.Reputation DESC) AS rn_active
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE
        u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
TopQuestions AS (
    SELECT
        pq.Id AS QuestionId,
        pq.Title,
        pq.OwnerUserId AS OwnerId,
        pq.CreationDate,
        pq.Score,
        pq.ViewCount,
        pq.AnswerCount,
        pq.Tags,
        ROW_NUMBER() OVER (ORDER BY pq.Score DESC, pq.ViewCount DESC) AS rn_question
    FROM
        Posts pq
    WHERE
        pq.PostTypeId = 1
        AND pq.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90' DAY)
),
AnswersWithFirstComment AS (
    SELECT
        pa.Id AS AnswerId,
        pa.ParentId AS QuestionId,
        pa.OwnerUserId AS AnswerUserId,
        pa.Score AS AnswerScore,
        pa.CreationDate AS AnswerDate,
        c.Id AS FirstCommentId,
        c.Text AS FirstCommentText,
        c.CreationDate AS FirstCommentDate,
        ROW_NUMBER() OVER (PARTITION BY pa.Id ORDER BY c.CreationDate ASC) AS rn_comment
    FROM
        Posts pa
        LEFT JOIN Comments c ON c.PostId = pa.Id
    WHERE
        pa.PostTypeId = 2
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.Location,
    ru.PostCount,
    ru.BadgeCount,
    ru.GoldBadgeCount,
    tq.QuestionId,
    tq.Title AS QuestionTitle,
    tq.Score AS QuestionScore,
    tq.ViewCount AS QuestionViews,
    CASE
        WHEN tq.Tags IS NOT NULL THEN (
            -- convert tags like '<tag1><tag2>' into count without using DB-specific functions
            LENGTH(tq.Tags) - LENGTH(REPLACE(tq.Tags, '><', '')) + CASE WHEN tq.Tags LIKE '<%>' THEN 0 ELSE 0 END
        ) / CASE WHEN LENGTH(REPLACE(tq.Tags, '><', '')) = LENGTH(tq.Tags) THEN NULL ELSE LENGTH('><') END
    ELSE 0
    END AS TagCount,
    (
        SELECT COUNT(1) FROM AnswersWithFirstComment a
        WHERE a.QuestionId = tq.QuestionId AND a.rn_comment = 1 AND a.FirstCommentId IS NOT NULL
    ) AS AnswersWithAtLeastOneComment,
    cr.Name AS LastCloseReason,
    ph.CreationDate AS CloseDate,
    (COALESCE(tq.Score,0) * 2 + COALESCE(tq.ViewCount,0) / 100.0)
        * (1 + COALESCE(ru.GoldBadgeCount,0) / NULLIF(ru.BadgeCount,0)) AS PopularityScore
FROM
    RecentActiveUsers ru
    INNER JOIN TopQuestions tq ON tq.OwnerId = ru.UserId AND tq.rn_question <= 5
    LEFT JOIN LATERAL (
        SELECT
            CAST(ph1.Comment AS INTEGER) AS CloseReasonId,
            ph1.CreationDate
        FROM
            PostHistory ph1
        WHERE
            ph1.PostId = tq.QuestionId
            AND ph1.PostHistoryTypeId = 10
        ORDER BY
            ph1.CreationDate DESC
        LIMIT 1
    ) ph ON TRUE
    LEFT JOIN CloseReasonTypes cr ON cr.Id = ph.CloseReasonId
WHERE
    ru.rn_active <= 20
GROUP BY
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.Location,
    ru.PostCount,
    ru.BadgeCount,
    ru.GoldBadgeCount,
    ru.rn_active,
    tq.QuestionId,
    tq.Title,
    tq.Score,
    tq.ViewCount,
    tq.Tags,
    tq.rn_question,
    cr.Name,
    ph.CreationDate
ORDER BY
    ru.rn_active,
    tq.rn_question;