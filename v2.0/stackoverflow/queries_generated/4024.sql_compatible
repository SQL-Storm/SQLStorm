WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 0 AND p.AnswerCount IS NOT NULL
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostsOwned,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentsMade,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND p.Id = c.PostId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostMetrics AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.PostTypeName,
        ua.DisplayName AS OwnerDisplayName,
        ua.Reputation AS OwnerReputation,
        ua.PostsOwned AS OwnerPostsOwned,
        rp.Score,
        rp.AnswerCount,
        rp.CreationDate,
        COALESCE(rp.AnswerCount * rp.Score, 0) AS WeightedScore,
        CASE
            WHEN rp.Score > 100 THEN 'HighScore'
            WHEN rp.Score > 10 THEN 'MediumScore'
            ELSE 'LowScore'
        END AS ScoreCategory,
        ua.LastPostActivity,
        ua.CommentsMade,
        CASE
            WHEN ua.LastPostActivity > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY) THEN 'ActiveRecent'
            ELSE 'InactivePast'
        END AS UserActivityStatus,
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5)
        ) AS EditCount,
        rp.OwnerUserId
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.rn <= 100
),
AggregatedPostHistory AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 END) AS DeleteVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 END) AS CommunityOwnedEvents,
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT PostId FROM PostMetrics)
    GROUP BY ph.PostId
)
SELECT
    pm.PostId,
    pm.Title,
    pm.PostTypeName,
    pm.OwnerDisplayName,
    pm.OwnerReputation,
    pm.OwnerPostsOwned,
    pm.Score,
    pm.AnswerCount,
    pm.CreationDate,
    pm.WeightedScore,
    pm.ScoreCategory,
    pm.UserActivityStatus,
    aph.CloseVotes,
    aph.DeleteVotes,
    aph.CommunityOwnedEvents,
    CASE
        WHEN aph.CloseVotes > 5 THEN 'FrequentlyClosed'
        WHEN aph.DeleteVotes > 3 THEN 'FrequentlyDeleted'
        ELSE 'StandardActivity'
    END AS HistoryCategory,
    CONCAT(
        LEFT(pm.Title, 20),
        '...'
    ) AS TruncatedTitle,
    CASE
        WHEN pm.OwnerReputation > 100000 THEN 'SuperUser'
        WHEN pm.OwnerReputation > 10000 THEN 'ExperiencedUser'
        ELSE 'RegularUser'
    END AS UserTier,
    COALESCE(ua.CommentsMade, 0) AS TotalCommentsMadeByOwner,
    CASE
        WHEN pm.LastPostActivity IS NULL OR ua.LastPostActivity IS NULL THEN 'Unknown'
        WHEN pm.LastPostActivity > ua.LastPostActivity THEN 'PostUpdatedAfterUserLastActive'
        ELSE 'UserUpdatedAfterPostLastActive'
    END AS ActivityTimeliness,
    CASE
        WHEN pm.EditCount > 5 THEN 'Highly Edited'
        WHEN pm.EditCount > 0 THEN 'Moderately Edited'
        ELSE 'Not Edited'
    END AS EditStatus
FROM PostMetrics pm
LEFT JOIN AggregatedPostHistory aph ON pm.PostId = aph.PostId
LEFT JOIN UserActivity ua ON pm.OwnerUserId = ua.UserId
WHERE pm.OwnerReputation > 5000
ORDER BY pm.WeightedScore DESC, pm.CreationDate ASC
LIMIT 50;