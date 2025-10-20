-- {"query": "322.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 22049} 
WITH
  base AS (
    SELECT p.Id AS PostId,
           p.PostTypeId,
           p.Title,
           p.Tags,
           p.CreationDate,
           p.LastActivityDate,
           p.Score,
           p.ViewCount,
           p.OwnerUserId,
           p.OwnerDisplayName AS OwnerName
    FROM Posts p
    WHERE p.CreationDate > NOW() - INTERVAL '2 years'
  ),
  votes AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
           SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyTotal
    FROM Votes v
    GROUP BY v.PostId
  ),
  comments AS (
    SELECT c.PostId,
           COUNT(*) AS CommentCount,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
  ),
  last_closed AS (
    SELECT ph.PostId,
           MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate
    FROM PostHistory ph
    GROUP BY ph.PostId
  ),
  last_migrated AS (
    SELECT ph.PostId,
           MAX(CASE WHEN ph.PostHistoryTypeId = 36 THEN ph.CreationDate END) AS LastMigratedDate
    FROM PostHistory ph
    GROUP BY ph.PostId
  ),
  gold_badge AS (
    SELECT b.UserId, 1 AS HasGold
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
  ),
  tag_counts AS (
    SELECT b.PostId,
           COUNT(*) AS TagCount
    FROM base b
    LEFT JOIN LATERAL UNNEST(string_to_array(substring(b.Tags from 2 for char_length(b.Tags) - 2), '><')) AS t(TagName) ON true
    GROUP BY b.PostId
  ),
  composed AS (
    SELECT
      b.PostId,
      b.PostTypeId,
      b.Title,
      b.OwnerName,
      b.CreationDate,
      b.LastActivityDate,
      b.Score,
      b.ViewCount,
      COALESCE(v.UpVotes, 0) AS UpVotes,
      COALESCE(v.DownVotes, 0) AS DownVotes,
      COALESCE(cm.CommentCount, 0) AS CommentCount,
      COALESCE(v.BountyTotal, 0) AS BountyTotal,
      cl.LastClosedDate,
      lm.LastMigratedDate,
      COALESCE(g.HasGold, 0) AS HasGold,
      COALESCE(tc.TagCount, 0) AS TagCount,
      cm.LastCommentDate,
      UPPER(SUBSTR(b.Title, 1, 12)) AS TitleSnippet,
      ROW_NUMBER() OVER (PARTITION BY b.PostTypeId ORDER BY (COALESCE(b.Score, 0) + COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) DESC NULLS LAST) AS rn,
      (SELECT COUNT(*) FROM Badges bb WHERE bb.UserId = b.OwnerUserId) AS OwnerBadgeCount
    FROM base b
    LEFT JOIN votes v ON v.PostId = b.PostId
    LEFT JOIN comments cm ON cm.PostId = b.PostId
    LEFT JOIN last_closed cl ON cl.PostId = b.PostId
    LEFT JOIN last_migrated lm ON lm.PostId = b.PostId
    LEFT JOIN gold_badge g ON g.UserId = b.OwnerUserId
    LEFT JOIN tag_counts tc ON tc.PostId = b.PostId
  ),
  top_set AS (
    SELECT *
    FROM composed
    WHERE PostTypeId IN (1,2)
      AND UpVotes - DownVotes > 0
    ORDER BY rn
    LIMIT 300
  ),
  late_set AS (
    SELECT *
    FROM composed
    WHERE PostTypeId IN (1,2)
      AND LastCommentDate >= NOW() - INTERVAL '14 days'
    ORDER BY LastActivityDate DESC
    LIMIT 300
  ),
  unioned AS (
    SELECT * FROM top_set
    UNION ALL
    SELECT * FROM late_set
  )
SELECT
  PostId,
  PostTypeId,
  Title,
  OwnerName,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  UpVotes,
  DownVotes,
  CommentCount,
  BountyTotal,
  LastClosedDate,
  LastMigratedDate,
  HasGold,
  TagCount,
  LastCommentDate,
  TitleSnippet,
  rn,
  OwnerBadgeCount
FROM unioned
ORDER BY PostTypeId, UpVotes DESC NULLS LAST
LIMIT 1000;