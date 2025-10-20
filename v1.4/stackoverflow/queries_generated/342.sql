-- {"query": "342.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17653} 
WITH
votes_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  GROUP BY v.PostId
),
comments_agg AS (
  SELECT c.PostId,
         COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
owner_badges AS (
  SELECT b.UserId,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         COUNT(*) AS TotalBadges
  FROM Badges b
  GROUP BY b.UserId
),
tag_lists AS (
  SELECT p.Id AS PostId,
         string_agg(t.TagName, ',') AS TagList
  FROM Posts p
  LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tn(TagName) ON TRUE
  LEFT JOIN Tags t ON t.TagName = tn.TagName
  GROUP BY p.Id
),
base AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.OwnerUserId AS OwnerUserId,
         p.CreationDate,
         p.LastActivityDate,
         p.ViewCount,
         p.Score,
         COALESCE(v.UpVotes, 0) AS UpVotes,
         COALESCE(v.DownVotes, 0) AS DownVotes,
         COALESCE(c.CommentCount, 0) AS CommentCount,
         u.DisplayName AS OwnerName,
         u.Reputation,
         COALESCE(ob.GoldBadges, 0) AS GoldBadges,
         COALESCE(ob.TotalBadges, 0) AS TotalBadges,
         tl.TagList,
         (SELECT cu.DisplayName
          FROM Comments c2
          LEFT JOIN Users cu ON cu.Id = c2.UserId
          WHERE c2.PostId = p.Id
          ORDER BY c2.CreationDate DESC
          LIMIT 1) AS MostRecentCommentAuthor,
         ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, (COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) DESC, p.CreationDate) AS rn
  FROM Posts p
  LEFT JOIN votes_agg v ON v.PostId = p.Id
  LEFT JOIN comments_agg c ON c.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN tag_lists tl ON tl.PostId = p.Id
  LEFT JOIN owner_badges ob ON ob.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '120 days')
)
SELECT PostId, Title, OwnerUserId, CreationDate, LastActivityDate, ViewCount, Score, UpVotes, DownVotes, CommentCount, OwnerName, Reputation, GoldBadges, TotalBadges, TagList, MostRecentCommentAuthor, rn
FROM base
WHERE rn <= 100
UNION ALL
SELECT
  -1 AS PostId,
  'Totals' AS Title,
  NULL AS OwnerUserId,
  NULL AS CreationDate,
  NULL AS LastActivityDate,
  NULL AS ViewCount,
  NULL AS Score,
  (SELECT SUM(UpVotes) FROM base) AS UpVotes,
  (SELECT SUM(DownVotes) FROM base) AS DownVotes,
  (SELECT SUM(CommentCount) FROM base) AS CommentCount,
  NULL AS OwnerName,
  NULL AS Reputation,
  NULL AS GoldBadges,
  NULL AS TotalBadges,
  NULL AS TagList,
  NULL AS MostRecentCommentAuthor,
  0 AS rn;