WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        u.Reputation,
        (u.UpVotes * 1.0 / NULLIF(u.UpVotes + u.DownVotes, 0)) * 100 AS UpvoteRatio,
        RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS RankInLocation,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore
    FROM Users u
), PostAnalysis AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2) AS TagList,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT SUM(v.VoteTypeId) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS VoteImpact
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
)
SELECT 
    us.DisplayName,
    us.Location,
    us.Reputation,
    pa.Score,
    pa.ViewCount,
    pa.CommentCount,
    CASE 
      WHEN pa.TagList IS NULL OR pa.TagList = '' THEN 0
      ELSE (LENGTH(pa.TagList) - LENGTH(REPLACE(pa.TagList, '><', ''))) / LENGTH('><') + 1
    END AS TagCount,
    (SELECT COUNT(DISTINCT t.TagName) 
     FROM Tags t
     WHERE EXISTS (
       SELECT 1 FROM (
         SELECT TRIM(tag) AS tag FROM (
           SELECT UNNEST(string_to_array(pa.TagList, '><')) AS tag
         ) s
       ) s2 WHERE s2.tag = t.TagName
     )
    ) AS ValidTags,
    (SELECT STRING_AGG(phType.Name, ', ' ORDER BY phType.Name) 
     FROM PostHistory ph 
     JOIN PostHistoryTypes phType ON ph.PostHistoryTypeId = phType.Id
     WHERE ph.PostId = pa.Id AND phType.Id IN (10,11,12)
    ) AS PostHistoryEvents,
    CASE 
        WHEN us.UpvoteRatio > 80 THEN 'High Quality'
        WHEN us.UpvoteRatio BETWEEN 60 AND 80 THEN 'Medium Quality'
        ELSE 'Low Quality'
    END AS ContributorQuality,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = us.Id AND v.VoteTypeId = 8) AS TotalBountyOffered,
    pa.Id AS PostId,
    pa.TagList
FROM UserStats us
LEFT JOIN PostAnalysis pa ON us.Id = pa.OwnerUserId
WHERE us.GoldBadges > 0
  AND us.AvgPostScore > (SELECT AVG(Score) FROM Posts)
  AND EXISTS (
    SELECT 1 
    FROM Votes v 
    WHERE v.UserId = us.Id 
      AND v.VoteTypeId = 2 
      AND v.CreationDate BETWEEN CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH AND CAST('2024-10-01 12:34:56' AS TIMESTAMP)
  )
UNION ALL
SELECT 
    'Community Wiki' AS DisplayName,
    'N/A' AS Location,
    0 AS Reputation,
    p.Score,
    p.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    CASE 
      WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
      ELSE (LENGTH(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2)) - LENGTH(REPLACE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><', ''))) / LENGTH('><') + 1
    END AS TagCount,
    NULL AS ValidTags,
    (SELECT STRING_AGG(phType.Name, ', ' ORDER BY phType.Name) 
     FROM PostHistory ph 
     JOIN PostHistoryTypes phType ON ph.PostHistoryTypeId = phType.Id
     WHERE ph.PostId = p.Id
    ) AS PostHistoryEvents,
    'System' AS ContributorQuality,
    NULL AS TotalBountyOffered,
    p.Id AS PostId,
    SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2) AS TagList
FROM Posts p
WHERE p.CommunityOwnedDate IS NOT NULL
  AND p.Id NOT IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL)
ORDER BY Score DESC NULLS LAST, Reputation DESC
LIMIT 100;