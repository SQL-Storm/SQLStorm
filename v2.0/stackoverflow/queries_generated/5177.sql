-- {"query": "5177.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 727} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    AVG(t.Count) AS AvgTagCount,
    SUM(CASE WHEN t.IsModeratorOnly = 0 THEN t.Count ELSE 0 END) AS VisibleCount
  FROM Tags t
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsCreated,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsMade,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) AS VotesCast
  FROM Users u
),
DetailedPost AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.Score,
    r.ViewCount,
    r.CreationDate,
    r.OwnerUserId,
    r.LastActivityDate,
    r.CommentCount,
    CASE WHEN EXISTS (
      SELECT 1 FROM PostLinks pl WHERE pl.PostId = r.PostId AND pl.RelatedPostId = r.OwnerUserId
    ) THEN 1 ELSE 0 END AS IsLinkedToOwner,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 2) AS UpModCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 3) AS DownModCount
  FROM RecentHot r
  WHERE r.rn = 1
),
Combined AS (
  SELECT
    d.*,
    t.TagName,
    ta.AvgTagCount,
    ta.VisibleCount,
    ua.UserId AS ActivityUserId
  FROM DetailedPost d
  LEFT JOIN TopTags t ON POSITION('<' || t.TagName || '>' IN d.Tags) > 0
  LEFT JOIN TopTags ta ON ta.TagName = t.TagName
  LEFT JOIN UserActivity ua ON ua.UserId = d.OwnerUserId
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.CreationDate,
  c.LastAccessDate,
  c.PostsCreated,
  c.CommentsMade,
  c.VotesCast,
  c.Title,
  c.Tags,
  c.Score,
  c.ViewCount,
  c.CreationDate AS PostCreationDate,
  c.LastActivityDate,
  c.CommentCount,
  c.IsLinkedToOwner,
  c.UpModCount,
  c.DownModCount,
  c.TagName,
  c.AvgTagCount,
  c.VisibleCount
FROM Combined c
ORDER BY c.Reputation DESC NULLS LAST, c.LastActivityDate DESC
LIMIT 100;