WITH LatestEdits AS (
  SELECT
    ph.PostId,
    ph.CreationDate,
    ph.UserId,
    U.DisplayName,
    ph.PostHistoryTypeId,
    RANK() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  LEFT JOIN Users U ON ph.UserId = U.Id
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
CommittedPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId
  FROM Posts p
)
SELECT
  le.PostId,
  le.CreationDate,
  le.UserId,
  le.DisplayName,
  le.PostHistoryTypeId
FROM LatestEdits le
JOIN CommittedPosts cp ON le.PostId = cp.Id
WHERE le.rn = 1;