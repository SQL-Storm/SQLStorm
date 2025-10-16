WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate))/86400) AS AvgDaysSincePost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE (p.PostTypeId IN (1, 2) OR p.PostTypeId IS NULL)
    GROUP BY u.Id, u.DisplayName
),
PostScoreRanks AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate) AS ScoreRank
    FROM Posts p
),
RecentEdits AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserId AS EditorId,
        u.DisplayName AS EditorName,
        ph.Comment
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17)
),
LinkedQuestions AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name IN ('Linked', 'Duplicate')
),
FinalResults AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        ua.PostsCount,
        ua.CommentsCount,
        ua.LastPostDate,
        ua.AvgDaysSincePost,
        p.Title,
        p.PostTypeId,
        p.Score,
        pR.ScoreRank,
        re.EditDate,
        re.EditorName,
        re.Comment AS LastEditComment,
        STRING_AGG(DISTINCT lt.Name, ', ') AS RelatedLinks,
        STRING_AGG(DISTINCT lq.LinkTypeName, ', ') AS LinkTypes
    FROM Users u
    LEFT JOIN UserActivity ua ON u.Id = ua.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostScoreRanks pR ON p.Id = pR.PostId
    LEFT JOIN RecentEdits re ON p.Id = re.PostId
    LEFT JOIN LinkedQuestions lq ON p.Id = lq.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ua.PostsCount,
        ua.CommentsCount,
        ua.LastPostDate,
        ua.AvgDaysSincePost,
        p.Title,
        p.PostTypeId,
        p.Score,
        pR.ScoreRank,
        re.EditDate,
        re.EditorName,
        re.Comment
)
SELECT *
FROM FinalResults
WHERE
    (COALESCE(PostsCount, 0) > 10 OR COALESCE(CommentsCount, 0) > 20)
    AND (LastPostDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180' DAY))
    AND (UserCreationDate IS NOT NULL AND (UserCreationDate IS NULL OR UserCreationDate IS NOT NULL)) -- placeholder to ensure column exists
ORDER BY Score DESC NULLS LAST, LastPostDate DESC NULLS LAST
LIMIT 100;