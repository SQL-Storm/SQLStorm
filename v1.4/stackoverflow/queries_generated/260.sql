-- {"query": "260.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8632} 
WITH
  RecentPosts AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Tags, p.LastActivityDate, p.Score, p.ViewCount, p.CreationDate
    FROM Posts p
    WHERE p.LastActivityDate >= current_timestamp - interval '180 days'
  ),
  PostActivity AS (
    SELECT rp.Id,
           rp.PostTypeId,
           rp.OwnerUserId,
           rp.Title,
           rp.Tags,
           rp.LastActivityDate,
           rp.Score,
           rp.ViewCount,
           rp.CreationDate,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentCount,
           (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) AS UpVotes,
           (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 3) AS DownVotes,
           (SELECT string_agg(t.TagName, ',')
              FROM unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS tn(tagName)
              LEFT JOIN Tags t ON t.TagName = tn.tagName) AS TagList
    FROM RecentPosts rp
  ),
  Ranked AS (
    SELECT pa.*,
           ROW_NUMBER() OVER (PARTITION BY pa.PostTypeId ORDER BY pa.Score DESC, pa.ViewCount DESC) AS rn
    FROM PostActivity pa
  ),
  UserSummary AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
           (SELECT MAX(Date) FROM Badges b WHERE b.UserId = u.Id) AS LastBadgeDate
    FROM Users u
  ),
  AllPosts AS (
    SELECT r.Id,
           r.Title,
           u.DisplayName AS OwnerName,
           u.Reputation,
           r.PostTypeId,
           pt.Name AS PostTypeName,
           r.Score,
           r.ViewCount,
           r.CommentCount,
           r.UpVotes,
           r.DownVotes,
           CASE WHEN (r.UpVotes + r.DownVotes) = 0 THEN NULL
                ELSE (r.UpVotes * 1.0) / (r.UpVotes + r.DownVotes)
           END AS UpDownRatio,
           r.TagList,
           ul.LastBadgeDate,
           us.BadgeCount,
           regexp_replace(COALESCE(u.WebsiteUrl, ''), 'https?://([^/]+).*', '\1', 'i') AS WebsiteDomain,
           (SELECT c.UserDisplayName FROM Comments c WHERE c.PostId = r.Id ORDER BY c.CreationDate DESC LIMIT 1) AS LastCommenterName,
           (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.Id) AS LinkCount,
           r.LastActivityDate
    FROM Ranked r
    JOIN Users u ON u.Id = r.OwnerUserId
    JOIN PostTypes pt ON pt.Id = r.PostTypeId
    LEFT JOIN UserSummary us ON us.UserId = u.Id
    LEFT JOIN (SELECT UserId, MAX(Date) AS LastBadgeDate FROM Badges GROUP BY UserId) ul ON ul.UserId = u.Id
  )
SELECT *
FROM AllPosts
WHERE rn = 1
UNION ALL
SELECT *
FROM (
  SELECT *
  FROM AllPosts
  WHERE LastActivityDate > current_timestamp - interval '7 days' AND rn <= 5
) AS recent
ORDER BY OwnerName, PostTypeName, Score DESC
LIMIT 200;