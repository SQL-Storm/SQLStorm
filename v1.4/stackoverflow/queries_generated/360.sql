-- {"query": "360.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 24770} 
WITH
Base AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    (COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) AS NetVotes,
    CASE
      WHEN p.Tags IS NULL OR length(p.Tags) < 4 THEN 0
      ELSE array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1)
    END AS TagCount,
    CASE WHEN (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) > 0 THEN 1 ELSE 0 END AS HasBadges
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) c ON c.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2)
),
RankedNet AS (
  SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    UpVotes,
    DownVotes,
    CommentCount,
    NetVotes,
    TagCount,
    HasBadges,
    ROW_NUMBER() OVER (
      PARTITION BY PostTypeId
      ORDER BY NetVotes DESC, UpVotes DESC, CommentCount DESC, TagCount DESC, CreationDate DESC
    ) AS NetRank
  FROM Base
),
NetTop AS (
  SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    UpVotes,
    DownVotes,
    CommentCount,
    NetVotes,
    TagCount,
    HasBadges,
    NetRank AS Rank,
    'net' AS RankSource
  FROM RankedNet
  ORDER BY NetVotes DESC, UpVotes DESC, CommentCount DESC, TagCount DESC
  LIMIT 150
),
BaseViews AS (
  SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    UpVotes,
    DownVotes,
    CommentCount,
    NetVotes,
    TagCount,
    HasBadges
  FROM Base
),
RankedViews AS (
  SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    UpVotes,
    DownVotes,
    CommentCount,
    NetVotes,
    TagCount,
    HasBadges,
    ROW_NUMBER() OVER (
      PARTITION BY PostTypeId
      ORDER BY ViewCount DESC, NetVotes DESC, TagCount DESC, CreationDate DESC
    ) AS ViewRank
  FROM BaseViews
),
TopByViews AS (
  SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    UpVotes,
    DownVotes,
    CommentCount,
    NetVotes,
    TagCount,
    HasBadges,
    ViewRank AS Rank,
    'views' AS RankSource
  FROM RankedViews
  ORDER BY ViewRank
  LIMIT 150
),
Combined AS (
  SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    UpVotes,
    DownVotes,
    CommentCount,
    NetVotes,
    TagCount,
    HasBadges,
    Rank,
    RankSource
  FROM NetTop
  UNION ALL
  SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    CreationDate,
    LastActivityDate,
    ViewCount,
    Score,
    UpVotes,
    DownVotes,
    CommentCount,
    NetVotes,
    TagCount,
    HasBadges,
    Rank,
    RankSource
  FROM TopByViews
)
SELECT *
FROM Combined
ORDER BY NetVotes DESC NULLS LAST, RankSource, Rank
LIMIT 200;