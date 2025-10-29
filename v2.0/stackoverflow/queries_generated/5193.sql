-- {"query": "5193.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1033} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.LastAccessDate >= NOW() - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS tag_rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
popular_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS post_rank
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.ClosedDate IS NULL
),
external_links AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.LinkTypeId = 1 OR pl.LinkTypeId = 3
),
aggregated AS (
  SELECT
    up.UserId,
    up.DisplayName AS UserDisplayName,
    up.Reputation,
    up.CreationDate AS UserCreationDate,
    up.LastAccessDate,
    up.Views,
    up.UpVotes,
    up.DownVotes,
    up.Location,
    up.WebsiteUrl,
    up.AboutMe,
    up.ProfileImageUrl,
    up.EmailHash,
    up.AccountId,
    SUM(CASE WHEN ro.post_rank IS NOT NULL THEN 1 ELSE 0 END) AS recent_top_posts,
    SUM(CASE WHEN ex.Id IS NOT NULL THEN 1 ELSE 0 END) AS has_external_links,
    MAX(p.post_rank) AS best_post_rank,
    MAX(p.Score) AS max_post_score,
    MAX(p.ViewCount) AS max_view_count
  FROM recent_user_activity up
  LEFT JOIN top_tags tt ON 1=1
  LEFT JOIN popular_posts p ON p.OwnerUserId = up.UserId
  LEFT JOIN external_links ex ON ex.PostId = p.PostId
  LEFT JOIN (
    SELECT 1 AS dummy
  ) ro ON ro.dummy = 1
  GROUP BY
    up.UserId, up.DisplayName, up.Reputation, up.CreationDate, up.LastAccessDate,
    up.Views, up.UpVotes, up.DownVotes, up.Location, up.WebsiteUrl, up.AboutMe,
    up.ProfileImageUrl, up.EmailHash, up.AccountId
)
SELECT
  a.UserId,
  a.UserDisplayName,
  a.Reputation,
  a.UserCreationDate,
  a.LastAccessDate,
  a.Views,
  a.UpVotes,
  a.DownVotes,
  a.Location,
  a.WebsiteUrl,
  a.AboutMe,
  a.ProfileImageUrl,
  a.EmailHash,
  a.AccountId,
  a.recent_top_posts,
  a.has_external_links,
  a.best_post_rank,
  a.max_post_score,
  a.max_view_count,
  STRING_AGG(DISTINCT tt.TagName, ',') FILTER (WHERE tt.tag_rn = 1) AS TopTags
FROM aggregated a
LEFT JOIN post_history_latest_tags phlt ON phlt.UserId = a.UserId
LEFT JOIN top_tags tt ON tt.TagName IN (SELECT TagName FROM Tags WHERE Id = phlt.TagId)
GROUP BY
  a.UserId,
  a.UserDisplayName,
  a.Reputation,
  a.UserCreationDate,
  a.LastAccessDate,
  a.Views,
  a.UpVotes,
  a.DownVotes,
  a.Location,
  a.WebsiteUrl,
  a.AboutMe,
  a.ProfileImageUrl,
  a.EmailHash,
  a.AccountId,
  a.recent_top_posts,
  a.has_external_links,
  a.best_post_rank,
  a.max_post_score,
  a.max_view_count
ORDER BY a.Reputation DESC, a.max_view_count DESC
LIMIT 100;