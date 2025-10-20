WITH UserActivityStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.Id) AS HistoryEdits,
        CAST(COUNT(DISTINCT CAST(c.Id AS BIGINT)) AS DOUBLE PRECISION) AS CommentedIdsCount
    FROM
        Users u
        LEFT JOIN PostHistory ph ON ph.UserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY
        u.Id,
        u.DisplayName
)
SELECT
    UserId,
    DisplayName,
    HistoryEdits,
    CommentedIdsCount
FROM
    UserActivityStats;