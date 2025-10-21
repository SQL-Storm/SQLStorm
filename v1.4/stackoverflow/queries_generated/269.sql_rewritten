-- {"query": "269.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 12495} 
WITH PostBase AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS Owner,
    u.Reputation AS OwnerReputation,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    CASE
      WHEN p.Tags IS NULL OR length(p.Tags) <= 2 THEN ''
      ELSE array_to_string(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'), ', ')
    END AS ParsedTags,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS UserBadges,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id) AS LastVoteDate,
    (p.Score * 1.0
     + (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
     - (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3)
     + (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) * 0.5) AS Engagement,
    EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - p.LastActivityDate)) / 86400.0 AS DaysSinceLastActivity,
    (SELECT COUNT(*) FROM Posts pp WHERE pp.OwnerUserId = p.OwnerUserId AND pp.Id <> p.Id) AS OtherPostsByOwner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
), Ranked AS (
  SELECT
    PostId, Title, Owner, OwnerReputation, CreationDate, ViewCount, Score, Tags, ParsedTags,
    UpVotes, DownVotes, CommentCount, UserBadges, LastVoteDate, Engagement, DaysSinceLastActivity,
    OtherPostsByOwner,
    ROW_NUMBER() OVER (PARTITION BY Owner ORDER BY Engagement DESC NULLS LAST) AS OwnerEngagementRank
  FROM PostBase
)
SELECT
  PostId,
  Title,
  Owner,
  OwnerReputation,
  CreationDate,
  ViewCount,
  Score,
  Tags,
  ParsedTags,
  UpVotes,
  DownVotes,
  CommentCount,
  UserBadges,
  LastVoteDate,
  Engagement,
  DaysSinceLastActivity,
  OtherPostsByOwner,
  OwnerEngagementRank
FROM Ranked
UNION ALL
SELECT
  p.Id AS PostId,
  p.Title,
  COALESCE(u.DisplayName, p.OwnerDisplayName) AS Owner,
  u.Reputation AS OwnerReputation,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.Tags,
  CASE
    WHEN p.Tags IS NULL OR length(p.Tags) <= 2 THEN ''
    ELSE array_to_string(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><'), ', ')
  END AS ParsedTags,
  0 AS UpVotes,
  0 AS DownVotes,
  0 AS CommentCount,
  0 AS UserBadges,
  NULL AS LastVoteDate,
  (p.Score * 1.0) AS Engagement,
  NULL AS DaysSinceLastActivity,
  (SELECT COUNT(*) FROM Posts pp WHERE pp.ParentId = p.Id) AS OtherPostsByOwner,
  NULL AS OwnerEngagementRank
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.ParentId IS NOT NULL
ORDER BY OwnerEngagementRank NULLS LAST, Engagement DESC NULLS LAST
LIMIT 50;