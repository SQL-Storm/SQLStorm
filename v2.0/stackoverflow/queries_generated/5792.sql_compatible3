WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AccountId,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.TagBased,
    ht.Id AS HistTypeId,
    ht.Name AS HistTypeName,
    ph.PostId AS HistPostId,
    ph.RevisionGUID,
    ph.CreationDate AS HistCreationDate,
    ph.UserDisplayName AS HistUserDisplayName,
    ph.Comment AS HistComment
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes ht ON ht.Id = ph.PostHistoryTypeId
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
    AND (p.ViewCount > 0 OR p.Score <> 0)
    AND (p.Tags IS NOT NULL OR p.Title IS NOT NULL)
),
TaggedAgg AS (
  SELECT
    p.Id,
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagScore AS (
  SELECT
    ta.Tag,
    COUNT(*) AS PostCount,
    SUM(COALESCE(p.Score,0)) AS ScoreSum,
    AVG(COALESCE(p.Score,0)) AS AvgScore
  FROM TaggedAgg ta
  JOIN Posts p ON p.Id = ta.Id
  GROUP BY ta.Tag
),
TopTags AS (
  SELECT
    t.Tag,
    t.PostCount,
    t.ScoreSum,
    t.AvgScore
  FROM TagScore t
  ORDER BY t.ScoreSum DESC, t.AvgScore DESC
  LIMIT 10
),
CrossJoined AS (
  SELECT
    rap.Id AS PostId,
    rap.Title,
    rap.OwnerUserId,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    rap.PostTypeId,
    rap.ParentId,
    rap.AcceptedAnswerId,
    rap.CommentCount,
    rap.AnswerCount,
    rap.FavoriteCount,
    rap.Body,
    rap.ContentLicense,
    NULL::text AS BadgeName,
    NULL::int AS BadgeClass,
    NULL::boolean AS TagBased,
    tht.Name AS HistTypeName,
    tht.Id AS HistTypeId,
    ph.PostId AS HistPostId,
    ph.RevisionGUID,
    ph.CreationDate AS HistCreationDate,
    ph.UserDisplayName AS HistUserDisplayName
  FROM RecentActivePosts rap
  LEFT JOIN TopTags tt ON position(tt.Tag in rap.Tags) > 0
  /* TagCountBadge table not found in Postgres error; remove or replace. */
  LEFT JOIN PostHistory ph ON ph.PostId = rap.Id
  LEFT JOIN PostHistoryTypes tht ON tht.Id = ph.PostHistoryTypeId
  LEFT JOIN PostLinks pl ON pl.PostId = rap.Id
  LEFT JOIN Tags t ON t.Id = (
    SELECT Id
    FROM Tags tg
    WHERE tg.TagName = (
      SELECT unnest(string_to_array(substr(rap.Tags, 2, length(rap.Tags)-2), '><'))
      LIMIT 1
    )
    LIMIT 1
  )
  WHERE rap.PostTypeId IN (1,2)
),
Final AS (
  SELECT DISTINCT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.CreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.Tags,
    c.PostTypeId,
    c.ParentId,
    c.AcceptedAnswerId,
    c.CommentCount,
    c.AnswerCount,
    c.FavoriteCount,
    c.Body,
    c.ContentLicense,
    c.BadgeName,
    c.BadgeClass,
    c.TagBased,
    c.HistTypeName,
    c.HistTypeId,
    c.HistPostId,
    c.RevisionGUID,
    c.HistCreationDate,
    c.HistUserDisplayName
  FROM CrossJoined c
  GROUP BY
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.CreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.Tags,
    c.PostTypeId,
    c.ParentId,
    c.AcceptedAnswerId,
    c.CommentCount,
    c.AnswerCount,
    c.FavoriteCount,
    c.Body,
    c.ContentLicense,
    c.BadgeName,
    c.BadgeClass,
    c.TagBased,
    c.HistTypeName,
    c.HistTypeId,
    c.HistPostId,
    c.RevisionGUID,
    c.HistCreationDate,
    c.HistUserDisplayName
  ORDER BY c.LastActivityDate DESC
  LIMIT 200
)
SELECT *
FROM Final
ORDER BY LastActivityDate DESC;