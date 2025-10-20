-- {"query": "43.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1165} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.ContentLicense,
    COALESCE(p.ParentId, 0) AS ParentId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate ASC
    ) AS rn
  FROM Posts p
  WHERE p.ClosedDate IS NULL
    AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreation,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS EditDate,
    ph.UserId AS EditorId,
    ph.UserDisplayName AS EditorName,
    ph.PostHistoryTypeId,
    ph.Comment AS EditComment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (5, 8, 15, 16) -- Edit Body, Edit Tags, Moderation events, Community Owned
),
LinkSummary AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE lt.Name ILIKE '%duplicate%') AS DuplicateLinks,
    COUNT(*) AS LinkCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
Aggregated AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.PostTypeId,
    rp.Tags,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.LastActivityDate,
    rp.LastEditDate,
    rp.ContentLicense,
    tostring_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><') AS TagArray,
    rt.Name AS PostTypeName,
    ua.Reputation AS OwnerReputation,
    ua.UserId AS ReporterUserId,
    ra.LastActivityDate AS LastSeen
  FROM RankedPosts rp
  LEFT JOIN PostTypes rt ON rp.PostTypeId = rt.Id
  LEFT JOIN UserActivity ua ON ua.UserId = rp.OwnerUserId
  LEFT JOIN (
    SELECT DISTINCT UserId, LastActivityDate
    FROM Posts
  ) ra ON ra.UserId = rp.OwnerUserId
  LEFT JOIN LinkSummary ls ON ls.PostId = rp.Id
)
SELECT
  a.PostId,
  a.Title,
  a.PostTypeName,
  a.OwnerDisplayName,
  a.OwnerReputation,
  a.ViewCount,
  a.Score,
  a.AnswerCount,
  a.CommentCount,
  a.FavoriteCount,
  a.CreationDate,
  a.LastActivityDate,
  a.LastEditDate,
  a.Tags,
  a.TagArray,
  a.ContentLicense,
  a.ReporterUserId,
  a.LastSeen,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS RelatedTags,
  ARRAY_AGG(DISTINCT e.EditorName) FILTER (WHERE e.EditorName IS NOT NULL) AS RecentEditors,
  ls.DuplicateLinks,
  ls.LinkCount
FROM Aggregated a
LEFT JOIN UnnestTagNames(a.TagArray) AS t ON TRUE
LEFT JOIN RecentEdits e ON e.PostId = a.PostId
GROUP BY
  a.PostId, a.Title, a.PostTypeName, a.OwnerDisplayName, a.OwnerReputation,
  a.ViewCount, a.Score, a.AnswerCount, a.CommentCount, a.FavoriteCount,
  a.CreationDate, a.LastActivityDate, a.LastEditDate, a.Tags, a.TagArray,
  a.ContentLicense, a.ReporterUserId, a.LastSeen, ls.DuplicateLinks, ls.LinkCount
ORDER BY a.Score DESC, a.ViewCount DESC
LIMIT 100;