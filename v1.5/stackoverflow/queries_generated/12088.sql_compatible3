WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) - COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS NetVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate) AS PostRank
  FROM 
    Posts p
  LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName
), 
TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS UserRank
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.DisplayName, u.Reputation
), 
PostTags AS (
  SELECT 
    pt.Id, 
    CAST(string_to_array(pt.Tags, '<') AS text[]) AS TagsArray
  FROM 
    Posts pt
  WHERE 
    pt.PostTypeId = 1
), 
TagCounts AS (
  SELECT 
    t.TagName, 
    COUNT(t.Id) AS TagCount
  FROM (
    SELECT 
      UNNEST(pt.TagsArray) AS TagName,
      pt.Id
    FROM 
      PostTags pt
  ) AS t
  GROUP BY 
    t.TagName
), 
PostHistorySummary AS (
  SELECT 
    ph.PostId, 
    COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
    MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS LastEditDate
  FROM 
    PostHistory ph
  GROUP BY 
    ph.PostId
)
SELECT 
  rp.Id, 
  rp.PostTypeId, 
  rp.CreationDate, 
  rp.Score, 
  rp.ViewCount, 
  rp.OwnerUserId, 
  rp.OwnerDisplayName,
  rp.NetVotes,
  rp.PostRank,
  tu.DisplayName AS TopUser,
  tu.Reputation,
  tu.GoldBadges,
  tu.SilverBadges,
  tu.BronzeBadges,
  tu.UserRank,
  tc.TagName,
  tc.TagCount,
  phs.EditCount,
  phs.LastEditDate
FROM 
  RankedPosts rp
JOIN 
  TopUsers tu ON rp.OwnerUserId = tu.Id
JOIN 
  PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
  TagCounts tc ON tc.TagName IN (SELECT UNNEST(pt.TagsArray))
LEFT JOIN 
  PostHistorySummary phs ON rp.Id = phs.PostId
WHERE 
  rp.PostRank <= 10 
  AND tu.UserRank <= 10
ORDER BY 
  rp.Score DESC, 
  rp.CreationDate;