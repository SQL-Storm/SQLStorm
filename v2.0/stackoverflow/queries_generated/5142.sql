-- {"query": "5142.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 924} 
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
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TagHotness AS (
  SELECT
    t.TagName,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views,
    COUNT(*) AS post_count,
    MAX(p.LastActivityDate) AS last_activity
  FROM Posts p
  CROSS APPLY (SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS TagName) AS t
  GROUP BY t.TagName
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
  LEFT JOIN Posts rp ON rp.OwnerUserId = u.Id AND rp.CreationDate >= NOW() - INTERVAL '180 days'
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
LEFT JOIN (
  SELECT
    ph.PostId,
    COUNT(*) AS TotalEdits
  FROM PostHistory ph
  WHERE ph.PostId IS NOT NULL
  GROUP BY ph.PostId
) pc ON pc.PostId = c.PostId
LEFT JOIN Votes v ON v.PostId = c.PostId AND v.VoteTypeId = 8
LEFT JOIN (
  SELECT
    vt.PostId,
    MAX(vt.CreationDate) AS LastVoteDate
  FROM Votes vt
  GROUP BY vt.PostId
) v2 ON v2.PostId = c.PostId
LEFT JOIN (
  SELECT
    pt.TagName
  FROM TopTags tt
  JOIN (SELECT TagName FROM TopTags) pt ON pt.TagName = tt.TagName
) t ON t.TagName = ANY(string_to_array(substring(c.Tags, 2, length(c.Tags)-2), '><'))
WHERE
  (c.Score > 0 OR c.CommentCount > 5)
  AND (c.OwnerUserId IS NULL OR c.OwnerUserId IS NOT NULL)
ORDER BY
  c.LastActivityDate DESC,
  c.Score DESC,
  c.ViewCount DESC
LIMIT 200;