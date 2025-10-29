WITH RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
),
-- Expand tags using string functions in a set-returning way where supported; otherwise keep aggregated TagHotness per tag parsed by splitting on '><'
TagHotness AS (
  SELECT
    tag.TagName,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views,
    COUNT(*) AS post_count,
    MAX(p.LastActivityDate) AS last_activity
  FROM Posts p
  JOIN (
    -- split tags stored like '<tag1><tag2>' into rows
    SELECT
      p2.Id AS PostId,
      TRIM(tag) AS TagName
    FROM Posts p2,
    (SELECT NULL) dummy, -- placeholder to allow correlated splitting below for SQL dialects without UNNEST; implementations may inline their own splitter
    LATERAL (
      SELECT regexp_split AS tag
      FROM UNNEST(string_to_array(substring(p2.Tags FROM 2 FOR char_length(p2.Tags) - 2), '><')) AS t(regexp_split)
    ) s
  ) tag ON tag.PostId = p.Id
  GROUP BY tag.TagName
),
TopTags AS (
  SELECT
    t.TagName,
    t.avg_score,
    t.total_views,
    t.post_count
  FROM TagHotness t
  ORDER BY t.avg_score DESC, t.total_views DESC
  LIMIT 50
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    COUNT(DISTINCT rp.Id) AS recent_posts
  FROM Users u
  LEFT JOIN Posts rp ON rp.OwnerUserId = u.Id AND rp.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY)
  GROUP BY
    u.Id, u.Reputation, u.DisplayName, u.AccountId, u.CreationDate, u.LastAccessDate,
    u.Views, u.UpVotes, u.DownVotes, u.ProfileImageUrl, u.Location, u.WebsiteUrl, u.AboutMe
),
Composite AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.Tags,
    r.LastActivityDate,
    r.AnswerCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId) AS CommentCount,
    (SELECT STRING_AGG(CONCAT(c.UserDisplayName, '(', c.Score, ')'), ', ') FROM Comments c WHERE c.PostId = r.PostId) AS CommentAuthors
  FROM RecentActive r
),
PostEdits AS (
  SELECT
    ph.PostId,
    COUNT(*) AS TotalEdits
  FROM PostHistory ph
  WHERE ph.PostId IS NOT NULL
  GROUP BY ph.PostId
),
LastVotes AS (
  SELECT
    vt.PostId,
    MAX(vt.CreationDate) AS LastVoteDate
  FROM Votes vt
  GROUP BY vt.PostId
),
DistinctTopTags AS (
  SELECT DISTINCT TagName FROM TopTags
)
SELECT
  c.PostId,
  c.PostTypeId,
  c.Title,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  c.Tags,
  c.LastActivityDate,
  c.AnswerCount,
  c.CommentCount,
  pc.TotalEdits,
  v.BountyAmount,
  v2.LastVoteDate,
  t.TagName
FROM Composite c
LEFT JOIN Posts p2 ON p2.Id = c.PostId
LEFT JOIN Users u ON u.Id = c.OwnerUserId
LEFT JOIN PostEdits pc ON pc.PostId = c.PostId
LEFT JOIN Votes v ON v.PostId = c.PostId AND v.VoteTypeId = 8
LEFT JOIN LastVotes v2 ON v2.PostId = c.PostId
LEFT JOIN DistinctTopTags t ON EXISTS (
  SELECT 1
  FROM (
    -- split c.Tags into rows; replace with dialect-specific splitter if UNNEST is unsupported
    SELECT TRIM(tag) AS tag
    FROM UNNEST(string_to_array(substring(c.Tags FROM 2 FOR char_length(c.Tags) - 2), '><')) AS taglist(tag)
  ) tagrows
  WHERE tagrows.tag = t.TagName
)
WHERE
  (c.Score > 0 OR c.CommentCount > 5)
  AND (c.OwnerUserId IS NULL OR c.OwnerUserId IS NOT NULL)
GROUP BY
  c.PostId,
  c.PostTypeId,
  c.Title,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.OwnerUserId,
  u.DisplayName,
  c.Tags,
  c.LastActivityDate,
  c.AnswerCount,
  c.CommentCount,
  pc.TotalEdits,
  v.BountyAmount,
  v2.LastVoteDate,
  t.TagName
ORDER BY
  c.LastActivityDate DESC,
  c.Score DESC,
  c.ViewCount DESC
LIMIT 200;