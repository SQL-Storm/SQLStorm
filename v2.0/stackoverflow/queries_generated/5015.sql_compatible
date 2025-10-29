WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.Tags,
    p.LastActivityDate,
    p.FavoriteCount,
    p.ContentLicense,
    up.DisplayName AS OwnerDisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users up ON p.OwnerUserId = up.Id
  WHERE p.PostTypeId IN (1,2)
),
Agg AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    rp.AnswerCount,
    rp.Tags,
    rp.LastActivityDate,
    rp.FavoriteCount,
    rp.ContentLicense,
    COUNT(*) OVER () AS TotalPosts
  FROM RankedPosts rp
  WHERE rp.rn <= 1000
),
Joined AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.Title,
    a.CreationDate,
    a.OwnerUserId,
    a.OwnerDisplayName,
    a.Reputation,
    a.ViewCount,
    a.Score,
    a.CommentCount,
    a.AnswerCount,
    a.Tags,
    a.LastActivityDate,
    a.FavoriteCount,
    a.ContentLicense,
    COALESCE(bl.LastEditDate, a.CreationDate) AS LastEventDate,
    COALESCE(bl2.Name, 'Unknown') AS LastEventSource,
    CASE
      WHEN a.PostTypeId = 1 THEN
        (SELECT COUNT(*) FROM Posts pr WHERE pr.ParentId = a.PostId AND pr.PostTypeId = 2)
      ELSE 0
    END AS UndeletedAnswerCount,
    CASE
      WHEN a.ViewCount > 1000 THEN 'HighExposure'
      WHEN a.ViewCount > 100 THEN 'ModerateExposure'
      ELSE 'LowExposure'
    END AS ExposureBand,
    CONCAT('Title=', a.Title, '; Tags=', COALESCE(a.Tags, ''), '; Owner=', a.OwnerDisplayName) AS MetaString
  FROM Agg a
  LEFT JOIN (
    SELECT p.Id, p.LastEditDate
    FROM Posts p
  ) bl ON bl.Id = a.PostId
  LEFT JOIN PostHistory ph ON ph.PostId = a.PostId
  LEFT JOIN PostTypes bl2 ON bl2.Id = a.PostTypeId
)
SELECT
  PostId,
  PostTypeId,
  Title,
  CreationDate,
  OwnerUserId,
  OwnerDisplayName,
  Reputation,
  ViewCount,
  Score,
  CommentCount,
  AnswerCount,
  Tags,
  LastActivityDate,
  FavoriteCount,
  ContentLicense,
  LastEventDate,
  LastEventSource,
  UndeletedAnswerCount,
  ExposureBand,
  MetaString
FROM Joined
WHERE ExposureBand <> 'LowExposure'
  AND LastEventDate > CreationDate - INTERVAL '180 days'
  AND (Tags IS NULL OR Tags <> '')
ORDER BY LastEventDate DESC, Score DESC
LIMIT 200;