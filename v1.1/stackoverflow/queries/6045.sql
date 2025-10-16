WITH TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AcceptedAnswerId,
    p.PostTypeId,
    pc.Count AS CommentCount,
    COALESCE(v.Count, 0) AS VoteCount
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM Comments
    GROUP BY PostId
  ) pc ON pc.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM Votes
    WHERE VoteTypeId IN (2,3,10,11,12,16)
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
PopularTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount
  FROM Tags t
  JOIN Posts p ON p.Id = t.Id
  WHERE COALESCE(t.IsModeratorOnly, false) = false
  GROUP BY t.TagName
  ORDER BY TagCount DESC
  LIMIT 20
),
CrossReference AS (
  SELECT
    l.Id AS LinkId,
    l.RelatedPostId,
    l.PostId,
    l.LinkTypeId,
    p.Title AS PostTitle,
    rp.Title AS RelatedPostTitle
  FROM PostLinks l
  JOIN Posts p ON p.Id = l.PostId
  JOIN Posts rp ON rp.Id = l.RelatedPostId
  WHERE l.LinkTypeId = 1
),
Computed AS (
  SELECT
    ta.UserId,
    ta.DisplayName,
    ta.Reputation,
    ta.Location,
    ta.Views,
    ta.UpVotes,
    ta.DownVotes,
    ta.AccountId,
    ra.PostId,
    ra.Title AS PostTitle,
    ra.CreationDate AS PostCreated,
    ra.LastActivityDate AS PostLastActive,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    ra.CommentCount,
    ra.VoteCount,
    pt.Name AS PostTypeName
  FROM TopAuthors ta
  LEFT JOIN RecentActivity ra ON ra.OwnerUserId = ta.UserId
  LEFT JOIN PostTypes pt ON pt.Id = ra.PostTypeId
  ORDER BY ta.Reputation DESC
  LIMIT 100
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.Location,
  c.Views,
  c.UpVotes,
  c.DownVotes,
  c.AccountId,
  c.PostId,
  c.PostTitle,
  c.PostCreated,
  c.PostLastActive,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.CommentCount,
  c.VoteCount,
  c.PostTypeName,
  ARRAY_AGG(DISTINCT rt.TagName) FILTER (WHERE rt.TagName IS NOT NULL) AS TopTags,
  ARRAY_AGG(DISTINCT rp.RelatedPostTitle) FILTER (WHERE rp.RelatedPostTitle IS NOT NULL) AS RelatedPosts
FROM Computed c
LEFT JOIN PopularTags rt ON TRUE
LEFT JOIN CrossReference rp ON rp.PostId = c.PostId
GROUP BY
  c.UserId, c.DisplayName, c.Reputation, c.Location, c.Views, c.UpVotes, c.DownVotes,
  c.AccountId, c.PostId, c.PostTitle, c.PostCreated, c.PostLastActive, c.Score, c.ViewCount,
  c.Tags, c.CommentCount, c.VoteCount, c.PostTypeName
ORDER BY c.Reputation DESC
LIMIT 200;