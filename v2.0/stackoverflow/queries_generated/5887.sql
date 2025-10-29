-- {"query": "5887.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 602} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUsage
  FROM Tags t
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName
  ORDER BY TagUsage DESC
  LIMIT 50
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
    u.ProfileImageUrl,
    u.Location,
    u.AboutMe,
    u.EmailHash,
    u.AccountId,
    IFNULL(b.TotalBadges,0) AS TotalBadges
  FROM Users u
  LEFT JOIN (
    SELECT
      UserId,
      COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
LastEditor AS (
  SELECT
    p.Id AS PostId,
    le.Id AS LastEditorId,
    le.DisplayName AS LastEditorName,
    p.LastEditDate,
    p.LastActivityDate
  FROM Posts p
  LEFT JOIN Users le ON p.LastEditorUserId = le.Id
)
SELECT
  rap.PostId,
  rap.Title,
  rap.CreationDate AS PostCreationDate,
  rap.LastActivityDate,
  rap.Score,
  rap.ViewCount,
  rap.Body,
  rap.Tags,
  rap.PostTypeId,
  rap.AnswerCount,
  rap.CommentCount,
  rap.FavoriteCount,
  ta.TagName,
  ta.TagUsage
FROM RecentActivePosts rap
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    t.TagName,
    t.Count AS TagUsage
  FROM Posts p
  JOIN Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
  WHERE t.TagName IS NOT NULL
) AS ta ON rap.PostId = ta.PostId
LEFT JOIN TopTags tt ON ta.TagName = tt.TagName
LEFT JOIN LastEditor le ON rap.PostId = le.PostId
LEFT JOIN UserActivity ua ON rap.OwnerUserId = ua.UserId
WHERE rap.PostTypeId IN (1,2)
ORDER BY rap.LastActivityDate DESC
LIMIT 100;