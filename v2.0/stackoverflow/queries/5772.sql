-- {"query": "5772.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 691}
WITH
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
UserInfluence AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC, u.Id) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
PopularPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.Tags,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount > 100
),
RedundantLinks AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,16,24,36)
),
Combined AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    up.DisplayName AS TopEditor,
    up.Reputation AS TopEditorRep,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.Tags AS PostTags,
    p.ViewCount,
    p.Score,
    p.CreationDate AS PostCreation,
    ro.LastActivityDate
  FROM TopTags t
  LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Users up ON p.OwnerUserId = up.Id
  LEFT JOIN RecentEdits re ON re.PostId = p.Id
  LEFT JOIN (
    SELECT OwnerUserId, MAX(LastActivityDate) AS LastActivityDate
    FROM Posts
    GROUP BY OwnerUserId
  ) ro ON ro.OwnerUserId = p.OwnerUserId
)
SELECT
  c.TagName,
  c.TagCount,
  c.TopEditor,
  c.TopEditorRep,
  c.PostId,
  c.PostTitle,
  c.PostTags,
  c.ViewCount,
  c.Score,
  c.PostCreation,
  c.LastActivityDate
FROM Combined c
WHERE c.PostId IS NOT NULL
ORDER BY c.TagCount DESC, c.TopEditorRep DESC, c.LastActivityDate DESC
LIMIT 100;