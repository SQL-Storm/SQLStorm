-- {"query": "5643.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1133}
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
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsCreated,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsMade,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) AS VotesCast
  FROM Users u
),
JoinedHierarchy AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.OwnerUserId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    r.Body,
    r.ContentLicense,
    EXTRACT(EPOCH FROM (r.LastActivityDate - r.CreationDate)) / 3600.0 / NULLIF(CASE WHEN r.AnswerCount > 0 THEN r.AnswerCount ELSE 1 END, 0) AS activity_density,
    COALESCE((
      SELECT 1.0 * tt.Count / NULLIF(t.TotalCount,0)
      FROM TopTags tt
      LEFT JOIN (SELECT SUM(Count) AS TotalCount FROM Tags) t ON TRUE
      WHERE (
        lower(tt.TagName) LIKE '%' || lower(coalesce(r.Title,'')) || '%'
        OR lower(tt.TagName) LIKE '%' || lower(coalesce(r.Tags,'')) || '%'
      )
      ORDER BY tt.Count DESC
      LIMIT 1
    ), 0) AS top_tag_influence
  FROM RecentActivePosts r
),
AdvancedJoin AS (
  SELECT
    jh.PostId,
    jh.PostTypeId,
    jh.OwnerUserId,
    jh.Title,
    jh.Tags,
    jh.CreationDate,
    jh.LastActivityDate,
    jh.Score,
    jh.ViewCount,
    jh.AnswerCount,
    jh.CommentCount,
    jh.FavoriteCount,
    jh.Body,
    jh.ContentLicense,
    jh.activity_density,
    jh.top_tag_influence,
    ua.UserId AS _ua_UserId,
    ua.DisplayName AS _ua_DisplayName,
    ua.Reputation AS _ua_Reputation,
    ua.UserCreationDate AS _ua_UserCreationDate,
    ua.LastAccessDate AS _ua_LastAccessDate,
    ua.Views AS _ua_Views,
    ua.UpVotes AS _ua_UpVotes,
    ua.DownVotes AS _ua_DownVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = jh.OwnerUserId) AS _owner_TotalVotes
  FROM JoinedHierarchy jh
  LEFT JOIN UserActivity ua ON jh.OwnerUserId = ua.UserId
),
FinalAgg AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.OwnerUserId,
    a.Title,
    a.Tags,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.AnswerCount,
    a.CommentCount,
    a.FavoriteCount,
    a.Body,
    a.ContentLicense,
    a.activity_density,
    a.top_tag_influence,
    a._ua_UserId,
    a._ua_DisplayName,
    a._ua_Reputation,
    a._ua_UserCreationDate,
    a._ua_LastAccessDate,
    a._ua_Views,
    a._ua_UpVotes,
    a._ua_DownVotes,
    a._owner_TotalVotes
  FROM AdvancedJoin a
  WHERE
    (a.Score > 0 OR a.AnswerCount > 0)
    AND (a.Tags IS NOT NULL AND LENGTH(a.Tags) > 0)
    AND (a.LastActivityDate > a.CreationDate - INTERVAL '14 days')
)
SELECT
  fa.PostId,
  fa.Title,
  fa.Tags,
  fa.CreationDate,
  fa.LastActivityDate,
  fa.ViewCount,
  fa.Score,
  fa.AnswerCount,
  fa.CommentCount,
  fa.FavoriteCount,
  fa.OwnerUserId,
  fu.DisplayName AS OwnerDisplayName,
  fu.Reputation AS OwnerReputation,
  fu.LastAccessDate AS OwnerLastAccessDate,
  fu.Views AS OwnerViews,
  fu.UpVotes AS OwnerUpVotes,
  fu.DownVotes AS OwnerDownVotes,
  fa.activity_density,
  fa.top_tag_influence
FROM FinalAgg fa
LEFT JOIN Users fu ON fa.OwnerUserId = fu.Id
ORDER BY fa.LastActivityDate DESC, fa.Score DESC
LIMIT 100;