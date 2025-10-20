-- {"query": "41.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 840} 
WITH 
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.Body,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TaggedSummary AS (
  SELECT
    p.Id,
    t.TagName,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY t.TagName) AS rn
  FROM Posts p
  CROSS APPLY (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t
  WHERE p.PostTypeId = 1
),
Aggregated AS (
  SELECT
    ra.PostId,
    ra.PostTypeId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerUserId,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.ContentLicense,
    ra.Body,
    ra.OwnerDisplayName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY ra.Id) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY ra.Id) AS DownVotesForPost,
    MAX(CASE WHEN b.Name IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY ra.Id) AS HasBadge
  FROM RecentActive ra
  LEFT JOIN Users u ON ra.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = ra.Id
  LEFT JOIN Badges b ON b.UserId = ra.OwnerUserId
), Windowed AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.LastActivityDate DESC) AS UserRecentRank,
    COUNT(*) OVER () AS TotalPostsInWindow
  FROM Aggregated a
)
SELECT
  w.PostId,
  w.PostTypeId,
  w.Title,
  w.CreationDate,
  w.LastActivityDate,
  w.OwnerUserId,
  w.OwnerDisplayName,
  w.OwnerReputation,
  w.Score,
  w.ViewCount,
  w.Tags,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.ContentLicense,
  w.Body,
  w.UpVotesForPost,
  w.DownVotesForPost,
  w.HasBadge,
  STRING_AGG(tg.TagName, ',') AS AllTags,
  MAX(CASE WHEN pg.PostId IS NOT NULL THEN pg.RelatedPostId END) AS RelatedPostId
FROM Windowed w
LEFT JOIN (
  SELECT PostId, RelatedPostId
  FROM PostLinks
  WHERE LinkTypeId = 1
) pg ON pg.PostId = w.PostId
LEFT JOIN TaggedSummary tg ON tg.Id = w.PostId AND tg.rn = 1
GROUP BY
  w.PostId, w.PostTypeId, w.Title, w.CreationDate, w.LastActivityDate,
  w.OwnerUserId, w.OwnerDisplayName, w.OwnerReputation, w.Score, w.ViewCount,
  w.Tags, w.AnswerCount, w.CommentCount, w.FavoriteCount, w.ContentLicense,
  w.Body, w.UpVotesForPost, w.DownVotesForPost, w.HasBadge, w.UserRecentRank, w.TotalPostsInWindow
ORDER BY w.LastActivityDate DESC, w.Score DESC
LIMIT 100;