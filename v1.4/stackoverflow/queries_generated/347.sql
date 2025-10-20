-- {"query": "347.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17373} 
WITH
  GoldBadges AS (
    SELECT b.UserId, COUNT(*) AS GoldBadges
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
  ),
  UsersWithBadge AS (
    SELECT u.Id,
           u.DisplayName AS DisplayName,
           u.Reputation,
           u.CreationDate,
           u.LastAccessDate,
           u.Location,
           u.WebsiteUrl,
           u.AccountId,
           COALESCE(gb.GoldBadges, 0) AS GoldBadges
    FROM Users u
    LEFT JOIN GoldBadges gb ON gb.UserId = u.Id
  ),
  RecentPosts AS (
    SELECT p.Id AS PostId,
           p.PostTypeId,
           p.Title,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           p.LastActivityDate,
           p.OwnerUserId,
           COALESCE(uwb.DisplayName, p.OwnerDisplayName) AS OwnerName,
           p.Tags,
           p.CommentCount,
           p.AcceptedAnswerId,
           p.ParentId,
           p.LastEditorUserId,
           p.LastEditorDisplayName,
           p.ContentLicense,
           uwb.Reputation AS OwnerReputation,
           uwb.GoldBadges AS OwnerGoldBadges
    FROM Posts p
    LEFT JOIN UsersWithBadge uwb ON uwb.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= NOW() - INTERVAL '365 days'
  ),
  Computed AS (
    SELECT rp.PostId,
           rp.PostTypeId,
           rp.Title,
           rp.Score,
           rp.ViewCount,
           rp.CreationDate,
           rp.LastActivityDate,
           rp.OwnerUserId,
           rp.OwnerName,
           rp.Tags,
           rp.CommentCount,
           rp.AcceptedAnswerId,
           rp.ParentId,
           rp.LastEditorUserId,
           rp.LastEditorDisplayName,
           rp.ContentLicense,
           rp.OwnerReputation,
           rp.OwnerGoldBadges,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountFromComments,
           (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId IN (8,9)) AS TotalBounty,
           (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpModCount,
           (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownModCount,
           CASE
             WHEN rp.Tags IS NULL OR rp.Tags = '' THEN 0
             WHEN LENGTH(rp.Tags) > 2 THEN COALESCE(array_length(string_to_array(substring(rp.Tags, 2, length(rp.Tags) - 2), '><'), 1), 0)
             ELSE 0
           END AS TagCount,
           (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId) AS LinkCount,
           (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 1) AS LinkedCount,
           (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS Duplicates
    FROM RecentPosts rp
  ),
  Ranked AS (
    SELECT c.*,
           ROW_NUMBER() OVER (
             PARTITION BY PostTypeId
             ORDER BY Score DESC NULLS LAST,
                      ViewCount DESC NULLS LAST,
                      LastActivityDate DESC NULLS LAST
           ) AS rn
    FROM Computed c
  ),
  TopQ AS (
    SELECT * FROM Ranked WHERE PostTypeId = 1 AND rn <= 20
  ),
  TopA AS (
    SELECT * FROM Ranked WHERE PostTypeId = 2 AND rn <= 20
  )
SELECT *
FROM TopQ
UNION ALL
SELECT *
FROM TopA
ORDER BY PostTypeId, rn;