-- {"query": "288.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7020} 
WITH
RecentPosts AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.LastActivityDate
  FROM Posts p
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
),
TagTokens AS (
  SELECT rp.Id AS PostId, tt.TagName
  FROM RecentPosts rp
  CROSS JOIN LATERAL unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><')) AS tt(TagName)
),
CommentCounts AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
VoteSums AS (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes
  GROUP BY PostId
),
PostEnvelope AS (
  SELECT rp.Id, rp.PostTypeId, rp.OwnerUserId, rp.Title, rp.Tags, rp.CreationDate, rp.Score, rp.ViewCount, rp.LastActivityDate,
         COALESCE(cc.CommentCount, 0) AS CommentCount,
         COALESCE(vs.UpVotes, 0) AS UpVotes,
         COALESCE(vs.DownVotes, 0) AS DownVotes
  FROM RecentPosts rp
  LEFT JOIN CommentCounts cc ON cc.PostId = rp.Id
  LEFT JOIN VoteSums vs ON vs.PostId = rp.Id
),
TopTagsByOwner AS (
  SELECT pe.OwnerUserId AS UserId, STRING_AGG(DISTINCT tt.TagName, ',') AS TopTags
  FROM PostEnvelope pe
  LEFT JOIN TagTokens tt ON tt.PostId = pe.Id
  GROUP BY pe.OwnerUserId
),
BronzeBadges AS (
  SELECT UserId, COUNT(*) AS BronzeCount
  FROM Badges
  WHERE Class = 3
  GROUP BY UserId
),
OwnerInfo AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation, COALESCE(u.Location, 'Unknown') AS Location
  FROM Users u
),
Activity30 AS (
  SELECT OwnerUserId AS UserId, TRUE AS Active30
  FROM Posts p
  WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY OwnerUserId
)
SELECT
  pe.Id AS PostId,
  pe.Title,
  pe.Tags,
  pe.CreationDate,
  pe.Score,
  pe.ViewCount,
  pe.CommentCount,
  pe.UpVotes,
  pe.DownVotes,
  o.DisplayName AS OwnerDisplayName,
  o.Reputation,
  o.Location,
  t.TopTags,
  COALESCE(b.BronzeCount, 0) AS BronzeBadges,
  CASE WHEN (pe.UpVotes - pe.DownVotes) > 100 THEN TRUE ELSE FALSE END AS IsHighlyVoted,
  COALESCE(a.Active30, FALSE) AS ActiveInLast30
FROM PostEnvelope pe
LEFT JOIN OwnerInfo o ON o.UserId = pe.OwnerUserId
LEFT JOIN TopTagsByOwner t ON t.UserId = pe.OwnerUserId
LEFT JOIN BronzeBadges b ON b.UserId = pe.OwnerUserId
LEFT JOIN Activity30 a ON a.UserId = pe.OwnerUserId
ORDER BY pe.Score DESC, pe.ViewCount DESC
LIMIT 200;