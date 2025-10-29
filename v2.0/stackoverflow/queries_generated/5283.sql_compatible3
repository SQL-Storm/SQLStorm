WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  JOIN (
    SELECT
      TRIM(tag_item) AS TagNameItem
    FROM (
      SELECT
        CASE
          WHEN SUBSTRING(TagNameRaw FROM 1 FOR 1) = '<' AND SUBSTRING(TagNameRaw FROM CHAR_LENGTH(TagNameRaw) FOR 1) = '>' THEN SUBSTRING(TagNameRaw FROM 2 FOR CHAR_LENGTH(TagNameRaw)-2)
          ELSE TagNameRaw
        END AS tags_concatenated
      FROM (
        SELECT t2.TagName AS TagNameRaw FROM Tags t2
      ) sub1
    ) sub2,
    LATERAL (
      SELECT regexp_split_to_table(sub2.tags_concatenated, E'\\>\\<') AS tag_item
    ) s
  ) x_tags ON true
  JOIN (
    SELECT
      regexp_split_to_table(
        CASE
          WHEN SUBSTRING(p2.Tags FROM 1 FOR 1) = '<' AND SUBSTRING(p2.Tags FROM CHAR_LENGTH(p2.Tags) FOR 1) = '>' THEN SUBSTRING(p2.Tags FROM 2 FOR CHAR_LENGTH(p2.Tags)-2)
          ELSE p2.Tags
        END,
        E'\\>\\<'
      ) AS TagNameItem2
    FROM Posts p2
  ) y_tags ON x_tags.TagNameItem = y_tags.TagNameItem2
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
  GROUP BY t.TagName
  ORDER BY PostCount DESC
  LIMIT 5
),
CorrelatedCommentStats AS (
  SELECT
    rp.PostId,
    COUNT(c.Id) AS CommentCountLast90
  FROM RecentActivePosts rp
  LEFT JOIN Comments c ON c.PostId = rp.PostId
    AND c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
  GROUP BY rp.PostId
),
VoteIntensity AS (
  SELECT
    vp.Id AS PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS Deletions,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN 1 ELSE 0 END) AS BountyCloses
  FROM Votes v
  JOIN Posts vp ON vp.Id = v.PostId
  WHERE v.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
  GROUP BY vp.Id
),
FlaggedPosts AS (
  SELECT
    p.Id AS PostId,
    COUNT(v.Id) AS FlagCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 16
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
AllData AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.LastActivityDate,
    r.OwnerUserId,
    r.PostTypeId,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.FavoriteCount,
    r.AnswerCount,
    ct.CommentCountLast90,
    vi.Upvotes,
    vi.Downvotes,
    vi.Deletions,
    vi.BountyStarts,
    vi.BountyCloses,
    fp.FlagCount,
    tt.TagName AS TopTag
  FROM RecentActivePosts r
  LEFT JOIN CorrelatedCommentStats ct ON ct.PostId = r.PostId
  LEFT JOIN VoteIntensity vi ON vi.PostId = r.PostId
  LEFT JOIN FlaggedPosts fp ON fp.PostId = r.PostId
  LEFT JOIN TopTags tt ON true
  WHERE r.PostTypeId IN (1,2)
)
SELECT
  ad.PostId,
  ad.Title,
  ad.Tags,
  ad.CreationDate,
  ad.LastActivityDate,
  ad.OwnerUserId,
  ad.PostTypeId,
  ad.Score,
  ad.ViewCount,
  ad.CommentCount,
  ad.FavoriteCount,
  ad.AnswerCount,
  ad.CommentCountLast90,
  ad.Upvotes,
  ad.Downvotes,
  ad.Deletions,
  ad.BountyStarts,
  ad.BountyCloses,
  ad.FlagCount,
  ad.TopTag
FROM AllData ad
ORDER BY ad.LastActivityDate DESC, ad.Score DESC
LIMIT 100;