WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.Tags,
    p.AcceptedAnswerId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
    MAX(CASE WHEN v.VoteTypeId IN (2,3) THEN v.CreationDate END) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON p.Id = v.PostId
  WHERE p.PostTypeId IN (1,2)
  GROUP BY
    p.Id, p.Title, p.PostTypeId, p.CreationDate, p.LastActivityDate,
    p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, p.Tags, p.AcceptedAnswerId
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
ActiveRank AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.PostTypeId,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerDisplayName,
    ra.OwnerUserId,
    ra.Tags,
    ra.AcceptedAnswerId,
    ROW_NUMBER() OVER (
      PARTITION BY ra.PostTypeId
      ORDER BY ra.LastActivityDate DESC, ra.Score DESC, ra.ViewCount DESC
    ) AS TypeRank
  FROM RecentActivity ra
),
StalePopular AS (
  SELECT
    a.PostId,
    a.Title,
    a.LastActivityDate,
    a.ViewCount
  FROM ActiveRank a
  WHERE a.LastActivityDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days')
    AND a.ViewCount > 1000
),
ComplexPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    (p.Body IS NOT NULL) AS HasBody,
    CASE
      WHEN p.Tags IS NULL OR CHAR_LENGTH(p.Tags) = 0 THEN 'untagged'
      ELSE 'tagged'
    END AS TagStatus,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'anonymous'
      WHEN u.Location IS NULL THEN 'location-unknown'
      ELSE u.Location
    END AS UserLocation,
    ('[' || COALESCE(p.Tags, '') || ']') AS TagArrayVisual,
    CHAR_LENGTH(p.Title) AS TitleLength
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
    AND (p.LastEditDate IS NULL OR p.LastEditDate >= p.CreationDate)
  GROUP BY
    p.Id, p.Title, p.Body, p.Tags, p.OwnerUserId, u.Location, p.LastEditDate, p.CreationDate
),
LatestHistory AS (
  SELECT
    p.Id AS PostId,
    ph.Id AS HistoryId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserDisplayName AS HistoryUser,
    ph.Comment
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  WHERE ph.Id IS NULL OR ph.CreationDate = (
    SELECT MAX(ph2.CreationDate)
    FROM PostHistory ph2
    WHERE ph2.PostId = p.Id
  )
),
FinalBundle AS (
  SELECT
    ar.PostId,
    ar.Title,
    ar.PostTypeId,
    ar.LastActivityDate,
    ar.Score,
    ar.ViewCount,
    ar.OwnerDisplayName,
    ar.Tags,
    ar.AcceptedAnswerId,
    lr.HistoryId,
    lr.HistoryDate,
    lr.Comment,
    cp.TagArrayVisual,
    cp.TitleLength,
    cp.UserLocation,
    cp.HasBody,
    cp.TagStatus,
    ar.OwnerUserId
  FROM ActiveRank ar
  LEFT JOIN LatestHistory lr ON lr.PostId = ar.PostId
  LEFT JOIN StalePopular sp ON sp.PostId = ar.PostId
  LEFT JOIN ComplexPosts cp ON cp.PostId = ar.PostId
  GROUP BY
    ar.PostId, ar.Title, ar.PostTypeId, ar.LastActivityDate, ar.Score, ar.ViewCount,
    ar.OwnerDisplayName, ar.Tags, ar.AcceptedAnswerId, lr.HistoryId, lr.HistoryDate, lr.Comment,
    cp.TagArrayVisual, cp.TitleLength, cp.UserLocation, cp.HasBody, cp.TagStatus, ar.OwnerUserId
)
SELECT
  fb.PostId,
  fb.Title,
  fb.PostTypeId,
  fb.LastActivityDate,
  fb.Score,
  fb.ViewCount,
  fb.OwnerDisplayName,
  fb.Tags,
  fb.AcceptedAnswerId,
  fb.HistoryDate,
  fb.Comment,
  fb.TagArrayVisual,
  fb.TitleLength,
  fb.UserLocation,
  fb.HasBody,
  fb.TagStatus,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = fb.OwnerUserId) AS DummyOwnerPostCount
FROM FinalBundle fb
ORDER BY fb.LastActivityDate DESC
LIMIT 100;