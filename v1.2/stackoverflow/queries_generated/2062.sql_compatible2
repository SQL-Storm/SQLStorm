WITH RecentRevisionCounts AS (
    SELECT
        ph.PostId,
        ph.UserId,
        COUNT(*) AS RecentPeHistoryCount
    FROM 
        PostHistory ph
    WHERE
        ph.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
        ph.PostId,
        ph.UserId
),
TopUsersQuestions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        EOQ.QPostsInLast60Days,
        COALESCE(EOQ.FullDataTrendingEdits, 0) AS TrendingEditScore
    FROM
        Users u
        LEFT JOIN LATERAL (
            SELECT COUNT(*) AS QPostsInLast60Days,
                   0 AS FullDataTrendingEdits
            FROM Posts p
            WHERE p.OwnerUserId = u.Id
              AND p.PostTypeId = 1
              AND p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '60' DAY
        ) EOQ ON TRUE
)
SELECT
    t.UserId,
    t.DisplayName,
    t.QPostsInLast60Days,
    t.TrendingEditScore,
    r.RecentPeHistoryCount
FROM
    TopUsersQuestions t
    LEFT JOIN RecentRevisionCounts r
      ON r.UserId = t.UserId
GROUP BY
    t.UserId,
    t.DisplayName,
    t.QPostsInLast60Days,
    t.TrendingEditScore,
    r.RecentPeHistoryCount;