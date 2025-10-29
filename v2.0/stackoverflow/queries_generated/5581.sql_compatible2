WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.Tags,
    p.Score,
    u.views AS Views,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    u.AccountId,
    COALESCE(u.ProfileImageUrl, '') AS avatar,
    COALESCE(b.TotalBadges, 0) AS BadgeCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON u.Id = b.UserId
  WHERE p.PostTypeId IN (1,2)
),
tag_expansion AS (
  SELECT
    ra.*,
    t.TagName,
    ROW_NUMBER() OVER (PARTITION BY ra.PostId ORDER BY t.TagName) AS tag_rn
  FROM recent_activity ra
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(ra.Tags FROM 2 FOR length(ra.Tags)-2), '><')) AS TagName
  ) AS t
),
windowed AS (
  SELECT
    te.PostId,
    te.Title,
    te.OwnerDisplayName,
    te.Reputation,
    te.Location,
    te.Views,
    te.Score,
    te.CommentCount,
    te.AnswerCount,
    te.FavoriteCount,
    te.CreationDate,
    te.LastActivityDate,
    te.ContentLicense,
    te.TagName,
    te.tag_rn,
    SUM(CASE WHEN te.TagName IS NULL THEN 0 ELSE 1 END) OVER (PARTITION BY te.PostId) AS TagCount
  FROM tag_expansion te
)
SELECT
  w.PostId,
  w.Title,
  w.OwnerDisplayName,
  w.Reputation,
  w.Location,
  w.Views,
  w.Score,
  w.CommentCount,
  w.AnswerCount,
  w.FavoriteCount,
  w.CreationDate,
  w.LastActivityDate,
  w.ContentLicense,
  w.TagName,
  w.TagCount
FROM windowed w
WHERE
  w.tag_rn = 1
  OR w.TagName IS NULL
ORDER BY
  w.LastActivityDate DESC,
  w.Score DESC
LIMIT 100;