-- {"query": "319.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17663} 
WITH base AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.PostTypeId,
    (string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))[1] AS FirstTag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
),
owner AS (
  SELECT b.PostId, b.Title, b.FirstTag, b.OwnerUserId, b.OwnerDisplayName, b.CreationDate, b.LastActivityDate, b.Score, b.ViewCount,
         u.Reputation
  FROM base b
  LEFT JOIN Users u ON u.Id = b.OwnerUserId
),
with_tot AS (
  SELECT o.PostId, o.Title, o.FirstTag, o.OwnerUserId, o.OwnerDisplayName, o.CreationDate, o.LastActivityDate, o.Score, o.ViewCount, o.Reputation,
         (SELECT COUNT(*) FROM Badges br WHERE br.UserId = o.OwnerUserId AND br.Class = 1) AS GoldBadges
  FROM owner o
),
with_votes AS (
  SELECT w.PostId, w.Title, w.FirstTag, w.OwnerUserId, w.OwnerDisplayName, w.CreationDate, w.LastActivityDate, w.Score, w.ViewCount, w.Reputation, w.GoldBadges,
         SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
  FROM with_tot w
  LEFT JOIN Votes v ON v.PostId = w.PostId
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY w.PostId, w.Title, w.FirstTag, w.OwnerUserId, w.OwnerDisplayName, w.CreationDate, w.LastActivityDate, w.Score, w.ViewCount, w.Reputation, w.GoldBadges
),
final AS (
  SELECT f.PostId, f.Title, f.FirstTag, f.OwnerUserId, f.OwnerDisplayName, f.CreationDate, f.LastActivityDate, f.Score, f.ViewCount, f.Reputation, f.GoldBadges,
         f.UpVotes, f.DownVotes,
         (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = f.OwnerUserId) AS AvgScoreByOwner,
         ROW_NUMBER() OVER (PARTITION BY f.OwnerUserId ORDER BY f.Score DESC, f.ViewCount DESC) AS RankByOwner
  FROM with_votes f
)
SELECT *
FROM final
WHERE Score > 50
UNION ALL
SELECT *
FROM final
WHERE ViewCount > 1000
ORDER BY Score DESC
LIMIT 250;