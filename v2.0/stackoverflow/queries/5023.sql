WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Location,
    u.WebsiteUrl,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViewsByAuthor,
    CASE
      WHEN p.ViewCount = 0 THEN 0
      ELSE (p.Score + p.CommentCount * 2 + p.FavoriteCount * 3) * 1.0 / NULLIF(p.ViewCount, 0)
    END AS InteractionDensity
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON u.Id = b.UserId
  WHERE p.PostTypeId IN (1, 2)
),
TagWordCounts AS (
  SELECT
    rp.PostId,
    unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags) - 2), '><')) AS Tag
  FROM RankedPosts rp
),
TagPopularity AS (
  SELECT
    Tag AS TagName,
    COUNT(*) AS TagCount
  FROM TagWordCounts
  GROUP BY Tag
),
TopTags AS (
  SELECT
    TagName,
    TagCount,
    ROW_NUMBER() OVER (ORDER BY TagCount DESC, TagName ASC) AS rn
  FROM TagPopularity
),
SelectedTag AS (
  SELECT TagName
  FROM TopTags
  WHERE rn = 1
)
SELECT
  rp.PostId,
  rp.Title,
  rp.Tags,
  rp.CreationDate,
  rp.ViewCount,
  rp.Score,
  rp.OwnerUserId,
  rp.UserDisplayName,
  rp.Reputation,
  rp.UserCreationDate,
  rp.Location,
  rp.WebsiteUrl,
  rp.BadgeCount,
  rp.CumulativeViewsByAuthor,
  rp.InteractionDensity,
  (
    SELECT ph.Comment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (14, 15)
      AND ph.PostId = rp.PostId
    ORDER BY ph.CreationDate DESC
    LIMIT 1
  ) AS LastModerationNote,
  NULL AS ExtraColumn
FROM RankedPosts rp
CROSS JOIN SelectedTag st
ORDER BY rp.CreationDate DESC
LIMIT 100;