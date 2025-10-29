WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagsSummary AS (
  SELECT
    t.TagName,
    SUM(1) AS TotalTagCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.CreationDate) AS LastPostDate
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS TagName
  ) t
  GROUP BY t.TagName
),
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.AccountId,
    CASE
      WHEN u.Reputation >= 10000 THEN 'Legendary'
      WHEN u.Reputation >= 1000 THEN 'Trusted'
      WHEN u.Reputation >= 100 THEN 'Contributor'
      ELSE 'Newbie'
    END AS Rank
  FROM Users u
  WHERE u.LastAccessDate > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30 days')
),
ComplexMetrics AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.OwnerUserId,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tc.TotalTagCount,
    tc.AvgPostScore,
    tc.LastPostDate,
    au.Rank,
    au.Reputation,
    rv.CreationDate AS RecentVoteDate,
    rv.VoteTypeId,
    ROW_NUMBER() OVER (PARTITION BY tp.PostId ORDER BY rv.CreationDate DESC) AS rn_vote
  FROM TopPosts tp
  LEFT JOIN TagsSummary tc ON TRUE
  LEFT JOIN ActiveUsers au ON tp.OwnerUserId = au.UserId
  LEFT JOIN RecentVotes rv ON tp.PostId = rv.PostId
  WHERE tp.rn = 1
)
SELECT
  cm.PostId,
  cm.Title,
  cm.OwnerUserId,
  cm.CreationDate,
  cm.Score,
  cm.ViewCount,
  cm.TotalTagCount,
  cm.AvgPostScore,
  cm.LastPostDate,
  cm.Rank AS OwnerRank,
  cm.Reputation,
  cm.RecentVoteDate,
  cm.VoteTypeId,
  cm.rn_vote
FROM ComplexMetrics cm
WHERE cm.rn_vote = 1
  AND cm.TotalTagCount IS NOT NULL
  AND cm.AvgPostScore > 0
ORDER BY cm.Score DESC, cm.ViewCount DESC
LIMIT 100;