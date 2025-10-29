-- {"query": "5201.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1152} 
WITH
RecentPostScores AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score + COALESCE(p.ViewCount,0)*0.5 + COALESCE(p.FavoriteCount,0)*2 DESC) AS rn_by_score
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
TopQuestions AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.Tags,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    r.rn_by_score
  FROM RecentPostScores r
  WHERE r.PostTypeId = 1 AND r.rn_by_score <= 10
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
    u.ProfileImageUrl,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate >= NOW() - INTERVAL '365 days') AS PostsLastYear,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate >= NOW() - INTERVAL '365 days') AS CommentsLastYear
  FROM Users u
  WHERE u.Reputation > 100
),
BadgeSummary AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    STRING_AGG(b.Name, ',') AS Badges
  FROM Badges b
  GROUP BY b.UserId
),
RecentTagWikis AS (
  SELECT
    t.Id AS TagWikiId,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
CrossLink AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.CreationDate >= NOW() - INTERVAL '365 days'
)
SELECT
  -- Top 5 Questions by Score with windowed rank and rich metadata
  t.PostId,
  t.Title,
  t.CreationDate,
  t.LastActivityDate,
  t.Score,
  t.ViewCount,
  t.AnswerCount,
  t.CommentCount,
  t.FavoriteCount,
  t.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  u.Location AS OwnerLocation,
  u.WebsiteUrl AS OwnerWebsite,
  u.AboutMe AS OwnerAbout,
  u.PostsLastYear,
  u.CommentsLastYear,
  rb.Badges AS OwnerBadges,
  t.Tags,
  rg.RecentTagWiki,
  crp.LastCloseReason
FROM TopQuestions t
JOIN UserActivity u ON t.OwnerUserId = u.UserId
LEFT JOIN BadgeSummary rb ON u.UserId = rb.UserId
LEFT JOIN (
  SELECT TagWikiId, TagName, Count, excerpt_post_id, wiki_post_id
  FROM RecentTagWikis
) rg ON rg.TagWikiId = t.TagWikiId
LEFT JOIN (
  SELECT PostId, MAX(CASE WHEN PostHistoryTypeId = 10 THEN Comment END) AS LastCloseReason
  FROM PostHistory ph
  WHERE ph.PostId IS NOT NULL
  GROUP BY PostId
) crp ON crp.PostId = t.PostId
ORDER BY t.rn_by_score ASC
LIMIT 1
UNION ALL
SELECT
  -- Fallback: include some correlated statistics on a sample of recent posts
  NULL::int AS PostId,
  NULL::varchar(300) AS Title,
  NULL::timestamp AS CreationDate,
  NULL::timestamp AS LastActivityDate,
  NULL::int AS Score,
  NULL::int AS ViewCount,
  NULL::int AS AnswerCount,
  NULL::int AS CommentCount,
  NULL::int AS FavoriteCount,
  NULL::int AS OwnerUserId,
  NULL::varchar(40) AS OwnerDisplayName,
  NULL::int AS OwnerReputation,
  NULL::varchar(100) AS OwnerLocation,
  NULL::varchar(200) AS OwnerWebsite,
  NULL::text AS OwnerAbout,
  NULL::int AS PostsLastYear,
  NULL::int AS CommentsLastYear,
  NULL::text AS OwnerBadges,
  NULL::varchar(4000) AS Tags,
  NULL::text AS RecentTagWiki,
  NULL::text AS LastCloseReason
LIMIT 0;