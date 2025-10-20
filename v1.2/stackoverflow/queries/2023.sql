WITH RecursiveAuthHist AS (
    SELECT
        ph.Id,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Text,
        ph.UserId,
        ph.PostId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2, 5, 8)
),
LatestAuth AS (
    SELECT
        rah.PostId,
        rah.UserId,
        rah.Id AS AuthHistId,
        rah.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY rah.PostId ORDER BY rah.CreationDate DESC, rah.Id DESC) AS rn
    FROM RecursiveAuthHist rah
),
FilteredLatestAuth AS (
    SELECT
        la.PostId,
        la.UserId,
        la.AuthHistId,
        la.CreationDate
    FROM LatestAuth la
    WHERE la.rn = 1
),
PostsWithAuth AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        fa.UserId AS AuthUserId,
        fa.AuthHistId,
        fa.CreationDate AS AuthCreationDate
    FROM Posts p
    LEFT JOIN FilteredLatestAuth fa
        ON p.Id = fa.PostId
)
SELECT
    p.PostId,
    p.OwnerUserId,
    p.PostCreationDate,
    p.Score,
    p.AuthUserId,
    p.AuthHistId,
    p.AuthCreationDate,
    CASE
        WHEN p.AuthCreationDate IS NOT NULL THEN
            EXTRACT(EPOCH FROM (p.AuthCreationDate - p.PostCreationDate)) -- seconds between post creation and latest auth event
        ELSE NULL
    END AS SecondsToAuth
FROM PostsWithAuth p
GROUP BY
    p.PostId,
    p.OwnerUserId,
    p.PostCreationDate,
    p.Score,
    p.AuthUserId,
    p.AuthHistId,
    p.AuthCreationDate
ORDER BY
    p.PostCreationDate DESC;