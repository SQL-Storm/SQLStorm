-- {"query": "5691.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 681}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Body,
    p.Tags AS TagsRaw,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
Leaderboard AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COALESCE(b.Count, 0) AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS Count
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
TaggedActivity AS (
  SELECT
    pt.Id AS PostId,
    pt.OwnerUserId,
    pt.Title,
    pt.CreationDate,
    pt.LastActivityDate,
    pt.Score,
    pt.ViewCount,
    STRING_AGG(tag, ',') AS TagsJoined
  FROM Posts pt
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(pt.Tags, 2, length(pt.Tags) - 2), '><')) AS tag
  ) s ON TRUE
  GROUP BY pt.Id, pt.OwnerUserId, pt.Title, pt.CreationDate, pt.LastActivityDate, pt.Score, pt.ViewCount
),
ActivityOverTime AS (
  SELECT
    DATE_TRUNC('day', p.LastActivityDate) AS activity_day,
    COUNT(*) AS posts_active
  FROM Posts p
  GROUP BY DATE_TRUNC('day', p.LastActivityDate)
),
Final AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    ru.DisplayName AS OwnerDisplayName,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    ro.BadgeCount AS OwnerBadges,
    lb.Reputation,
    lb.Views,
    lb.UpVotes,
    lb.DownVotes,
    ta.TagsJoined,
    aot.activity_day,
    aot.posts_active
  FROM RecentActivePosts rp
  LEFT JOIN Leaderboard lb ON lb.UserId = rp.OwnerUserId
  LEFT JOIN Users ru ON ru.Id = rp.OwnerUserId
  LEFT JOIN TaggedActivity ta ON ta.PostId = rp.PostId
  LEFT JOIN Leaderboard ro ON ro.UserId = rp.OwnerUserId
  LEFT JOIN ActivityOverTime aot ON aot.activity_day = DATE_TRUNC('day', rp.LastActivityDate)
  WHERE rp.Score IS NOT NULL
)
SELECT *
FROM Final
ORDER BY LastActivityDate DESC
LIMIT 100;