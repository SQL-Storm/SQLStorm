-- {"query": "306.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 21712} 
WITH
PostBase AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    COALESCE(u.DisplayName, '') AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1
),
TagInfo AS (
  SELECT b.PostId,
         CASE
           WHEN t.Tags IS NULL THEN ''
           WHEN length(t.Tags) <= 2 THEN ''
           ELSE array_to_string(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '><'), '|')
         END AS TagList,
         CASE
           WHEN t.Tags IS NULL THEN 0
           WHEN length(t.Tags) <= 2 THEN 0
           ELSE array_length(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '><'), 1)
         END AS TagCount
  FROM PostBase b
  LEFT JOIN Posts t ON t.Id = b.PostId
),
Edits AS (
  SELECT PostId, COUNT(*) AS EditCount
  FROM PostHistory
  WHERE PostHistoryTypeId IN (4,5,6,24)
  GROUP BY PostId
),
VoteSums AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes
  GROUP BY PostId
),
LastComment AS (
  SELECT PostId, MAX(CreationDate) AS LastCommentDate
  FROM Comments
  GROUP BY PostId
),
LinkedCounts AS (
  SELECT PostId,
         SUM(CASE WHEN LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCount,
         SUM(CASE WHEN LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount
  FROM PostLinks
  GROUP BY PostId
),
BadgeCounts AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
)
SELECT
  pb.PostId,
  pb.Title,
  pb.OwnerUserId AS OwnerId,
  pb.OwnerDisplayName,
  pb.OwnerReputation,
  pb.CreationDate,
  pb.LastActivityDate,
  COALESCE(pb.ViewCount, 0) AS ViewCount,
  COALESCE(pb.Score, 0) AS Score,
  COALESCE(pb.AnswerCount, 0) AS AnswerCount,
  COALESCE(pb.CommentCount, 0) AS CommentCount,
  COALESCE(ti.TagList, '') AS TagList,
  COALESCE(ti.TagCount, 0) AS TagCount,
  COALESCE(e.EditCount, 0) AS EditCount,
  COALESCE(vs.UpVotes, 0) AS UpVotes,
  COALESCE(vs.DownVotes, 0) AS DownVotes,
  (COALESCE(pb.Score, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) AS NetScore,
  LastComment.LastCommentDate,
  COALESCE(bc.GoldBadges, 0) AS GoldBadges,
  COALESCE(bc.SilverBadges, 0) AS SilverBadges,
  COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(lc.LinkedCount, 0) AS LinkedCount,
  COALESCE(lc.DuplicateCount, 0) AS DuplicateCount,
  (
    0.6 * (COALESCE(pb.Score, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0))
    + 0.25 * LN(1 + COALESCE(pb.ViewCount, 0))
    + 0.15 * COALESCE(e.EditCount, 0)
    + 0.15 * COALESCE(lc.LinkedCount, 0)
    + 0.15 * COALESCE(lc.DuplicateCount, 0)
  ) AS HotScore,
  (
    SELECT COUNT(*)
    FROM PostHistory ph
    WHERE ph.PostId = pb.PostId AND ph.PostHistoryTypeId = 10
  ) > 0 AS HasClosedVote
FROM PostBase pb
LEFT JOIN TagInfo ti ON ti.PostId = pb.PostId
LEFT JOIN Edits e ON e.PostId = pb.PostId
LEFT JOIN VoteSums vs ON vs.PostId = pb.PostId
LEFT JOIN LastComment LastComment ON LastComment.PostId = pb.PostId
LEFT JOIN LinkedCounts lc ON lc.PostId = pb.PostId
LEFT JOIN BadgeCounts bc ON bc.UserId = pb.OwnerUserId
WHERE ti.TagCount > 0
UNION ALL
SELECT
  pb.PostId,
  pb.Title,
  pb.OwnerUserId AS OwnerId,
  pb.OwnerDisplayName,
  pb.OwnerReputation,
  pb.CreationDate,
  pb.LastActivityDate,
  COALESCE(pb.ViewCount, 0) AS ViewCount,
  COALESCE(pb.Score, 0) AS Score,
  COALESCE(pb.AnswerCount, 0) AS AnswerCount,
  COALESCE(pb.CommentCount, 0) AS CommentCount,
  COALESCE(ti.TagList, '') AS TagList,
  COALESCE(ti.TagCount, 0) AS TagCount,
  COALESCE(e.EditCount, 0) AS EditCount,
  COALESCE(vs.UpVotes, 0) AS UpVotes,
  COALESCE(vs.DownVotes, 0) AS DownVotes,
  (COALESCE(pb.Score, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0)) AS NetScore,
  LastComment.LastCommentDate,
  COALESCE(bc.GoldBadges, 0) AS GoldBadges,
  COALESCE(bc.SilverBadges, 0) AS SilverBadges,
  COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(lc.LinkedCount, 0) AS LinkedCount,
  COALESCE(lc.DuplicateCount, 0) AS DuplicateCount,
  (
    0.6 * (COALESCE(pb.Score, 0) + COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0))
    + 0.25 * LN(1 + COALESCE(pb.ViewCount, 0))
    + 0.15 * COALESCE(e.EditCount, 0)
    + 0.15 * COALESCE(lc.LinkedCount, 0)
    + 0.15 * COALESCE(lc.DuplicateCount, 0)
  ) AS HotScore,
  (
    SELECT COUNT(*)
    FROM PostHistory ph
    WHERE ph.PostId = pb.PostId AND ph.PostHistoryTypeId = 10
  ) > 0 AS HasClosedVote
FROM PostBase pb
LEFT JOIN TagInfo ti ON ti.PostId = pb.PostId
LEFT JOIN Edits e ON e.PostId = pb.PostId
LEFT JOIN VoteSums vs ON vs.PostId = pb.PostId
LEFT JOIN LastComment LastComment ON LastComment.PostId = pb.PostId
LEFT JOIN LinkedCounts lc ON lc.PostId = pb.PostId
LEFT JOIN BadgeCounts bc ON bc.UserId = pb.OwnerUserId
WHERE ti.TagCount = 0
ORDER BY HotScore DESC
LIMIT 200;