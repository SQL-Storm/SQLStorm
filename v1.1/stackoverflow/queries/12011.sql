WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankByScore,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS RankByViewCount,
    p.Tags
  FROM 
    Posts p
  JOIN 
    Users u ON p.OwnerUserId = u.Id
  WHERE 
    p.PostTypeId IN (1, 2)
),
TopUsers AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.DisplayName, u.Reputation
),
PostHistorySummary AS (
  SELECT 
    ph.PostId,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1 END) AS InitialEdits,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS SubsequentEdits,
    COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseReopenActions
  FROM 
    PostHistory ph
  GROUP BY 
    ph.PostId
),
TagUsage AS (
  SELECT 
    t.TagName,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore
  FROM 
    Tags t
  JOIN 
    Posts p ON POSITION(t.TagName IN REPLACE(REPLACE(p.Tags, '<', ''), '>', ' ')) > 0
  GROUP BY 
    t.TagName
),
UserActivity AS (
  SELECT 
    u.Id,
    u.DisplayName,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes
  FROM 
    Users u
  LEFT JOIN 
    Comments c ON u.Id = c.UserId
  LEFT JOIN 
    Votes v ON u.Id = v.UserId
  GROUP BY 
    u.Id, u.DisplayName
)
SELECT 
  rp.Id,
  rp.PostTypeId,
  rp.Score,
  rp.ViewCount,
  rp.CreationDate,
  rp.OwnerDisplayName,
  rp.RankByScore,
  rp.RankByViewCount,
  tag.TagName,
  tag.PostCount,
  tag.TotalScore,
  ua.CommentCount,
  ua.VoteCount,
  ua.NetVotes,
  phs.InitialEdits,
  phs.SubsequentEdits,
  phs.CloseReopenActions
FROM 
  RankedPosts rp
JOIN 
  TopUsers tu ON rp.OwnerUserId = tu.Id
JOIN 
  PostHistorySummary phs ON rp.Id = phs.PostId
JOIN 
  TagUsage tag ON POSITION(tag.TagName IN REPLACE(REPLACE(rp.Tags, '<', ''), '>', ' ')) > 0
JOIN 
  UserActivity ua ON rp.OwnerUserId = ua.Id
WHERE 
  rp.RankByScore <= 10 
  AND rp.RankByViewCount <= 10
ORDER BY 
  rp.Score DESC, 
  rp.ViewCount DESC;