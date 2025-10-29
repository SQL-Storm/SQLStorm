-- {"query": "5439.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 824} 
WITH
RecentUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreated,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    c.TagBased,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
FilteredPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ClosedDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= dateadd(day, -365, current_timestamp)
),
PostTagExplode AS (
  SELECT
    fp.PostId,
    t.TagName
  FROM FilteredPosts fp
  CROSS APPLY (
    SELECT unnest(string_to_array(substring(fp.Tags, 2, length(fp.Tags)-2), '><')) AS TagName
  ) AS t
),
Joined AS (
  SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.ClosedDate,
    rp.ContentLicense,
    pt.TagName AS TagExploded
  FROM RecentUserActivity rua
  LEFT JOIN FilteredPosts rp ON rp.OwnerUserId = rua.UserId
  LEFT JOIN PostTagExplode pt ON pt.PostId = rp.PostId
  WHERE rp.PostTypeId IN (1,2) -- Questions and Answers
),
Windowed AS (
  SELECT
    j.*,
    ROW_NUMBER() OVER (
      PARTITION BY j.TagExploded
      ORDER BY j.LastActivityDate DESC
    ) AS rn_by_tag
  FROM Joined j
),
Final AS (
  SELECT
    w.UserId,
    w.DisplayName,
    w.Reputation,
    w.PostId,
    w.Title,
    w.Score,
    w.ViewCount,
    w.CreationDate,
    w.LastActivityDate,
    w.ParentId,
    w.AcceptedAnswerId,
    w.CommentCount,
    w.FavoriteCount,
    w.Body,
    w.LastEditorUserId,
    w.LastEditDate,
    w.ClosedDate,
    w.ContentLicense,
    w.TagExploded
  FROM Windowed w
  WHERE w.rn_by_tag = 1
)
SELECT
  DISTINCT
  f.UserId,
  f.DisplayName,
  f.Reputation,
  f.PostId,
  f.Title,
  f.Score,
  f.ViewCount,
  f.CreationDate,
  f.LastActivityDate,
  f.ParentId,
  f.AcceptedAnswerId,
  f.CommentCount,
  f.FavoriteCount,
  f.Body,
  f.LastEditorUserId,
  f.LastEditDate,
  f.ClosedDate,
  f.ContentLicense,
  f.TagExploded
FROM Final f
ORDER BY f.Reputation DESC, f.LastActivityDate DESC
LIMIT 100;