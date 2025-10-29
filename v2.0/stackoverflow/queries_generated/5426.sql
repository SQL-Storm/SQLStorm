-- {"query": "5426.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 924} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.Body,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.ViewCount * 0.7 + p.Score * 1.5 + DATE_PART('epoch', NOW() - p.CreationDate) * -0.2
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
Filtered AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerUserId,
    rp.Tags,
    rp.PostTypeId,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.Body
  FROM RankedPosts rp
  WHERE rp.rn <= 100
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.AboutMe,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT COUNT(*) FROM Posts pt WHERE pt.OwnerUserId = u.Id) AS PostCount
  FROM Users u
),
Correlation AS (
  SELECT
    f.Id AS PostId,
    f.Title,
    f.CreationDate,
    f.ViewCount,
    f.Score,
    f.OwnerUserId,
    f.Tags,
    f.PostTypeId,
    f.LastActivityDate,
    f.CommentCount,
    f.FavoriteCount,
    f.AcceptedAnswerId,
    f.ParentId,
    f.LastEditorUserId,
    f.LastEditDate,
    f.Body,
    us.UserId AS OwnerUserId_InStats
  FROM Filtered f
  LEFT JOIN UserStats us ON f.OwnerUserId = us.UserId
),
ComplexFilters AS (
  SELECT
    c.*,
    (POSITION('<python>' IN c.Tags) > 0) AS HasPythonTag,
    (c.Score > 0) AS PositiveScore,
    (c.ViewCount > 1000) AS MegaViewed,
    (c.LastActivityDate > c.CreationDate + INTERVAL '30 days') AS ActiveLate
  FROM Correlation c
  LEFT JOIN Badges b ON b.UserId = c.OwnerUserId
),
Joint AS (
  SELECT
    cf.*,
    CASE
      WHEN cf.PostTypeId = 1 THEN 'Question'
      WHEN cf.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    (SELECT STRING_AGG(t.TagName, ',') FROM Tags t WHERE t.Id = (SELECT unnest(string_to_array(cf.Tags, '>') )::int) LIMIT 1) AS SampleTag
  FROM ComplexFilters cf
)
SELECT
  j.PostId,
  j.Title,
  j.PostKind,
  j.CreationDate,
  j.LastActivityDate,
  j.ViewCount,
  j.Score,
  j.OwnerUserId,
  j.DisplayName AS OwnerDisplayName,
  j.Location AS OwnerLocation,
  j.HasPythonTag,
  j.PositiveScore,
  j.MegaViewed,
  j.ActiveLate,
  j.SampleTag,
  j.UserCreationDate,
  j.BadgeCount,
  j.PostCount,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = j.PostId) AS ChildPostCount,
  (SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = j.PostId) AS LastVoteDate
FROM Joint j
ORDER BY
  j.MegaViewed DESC,
  j.Score DESC,
  j.CreationDate ASC
LIMIT 100;