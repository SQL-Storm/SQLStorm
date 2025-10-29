-- {"query": "5104.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 807} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.FavoriteCount,
    p.AnswerCount,
    p.CommentCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.LastActivityDate >= CURRENT_DATE - INTERVAL '90 days'
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.Views DESC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
PostHistoryStats AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDateMax,
    COUNT(*) AS HistoryCount,
    MAX(ph.CreationDate) AS LastRevisionDate
  FROM PostHistory ph
  GROUP BY ph.PostId, ph.PostHistoryTypeId
),
RecentPostLinks AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE pl.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
),
TaggedTagWiki AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
)
SELECT
  rp.Id AS PostId,
  rp.PostTypeId,
  pt.Name AS PostTypeName,
  rp.Title,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.ReputationImpact := (CASE WHEN rp.PostTypeId = 1 THEN rp.Score ELSE NULL END) AS ScoreForBenchmark,
  rp.ViewCount,
  rp.Tags,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  ru.UserId,
  ru.DisplayName AS OwnerDisplayName,
  ru.Reputation,
  ru.CreationDate AS OwnerCreationDate,
  ru.LastAccessDate AS OwnerLastAccessDate,
  ru.Location,
  ru.Views AS OwnerViews,
  ru.UpVotes AS OwnerUpVotes,
  ru.DownVotes AS OwnerDownVotes,
  ru.AccountId,
  phs.HistoryCount,
  phs.ClosedDateMax,
  rpl.LinkTypeName,
  rp.ContentLicense,
  tgw.TagName AS MostUsedTag
FROM RecentActivePosts rp
LEFT JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN TopUsers ru ON rp.OwnerUserId = ru.UserId
LEFT JOIN PostHistoryStats phs ON rp.Id = phs.PostId
LEFT JOIN RecentPostLinks rpl ON rp.Id = rpl.PostId
LEFT JOIN Tags t ON t.Id = (SELECT UNNEST(string_to_array(rp.Tags, '><'))::int[] LIMIT 1)
LEFT JOIN TaggedTagWiki tgw ON tgw.TagName = (SELECT UNNEST(string_to_array(rp.Tags, '><'))::text LIMIT 1)
ORDER BY rp.LastActivityDate DESC, rp.Score DESC
LIMIT 1000;