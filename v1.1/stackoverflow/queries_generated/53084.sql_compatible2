WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, COUNT(p.Id) AS PostCount, SUM(p.Score) AS TotalScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= '2020-01-01' AND p.PostTypeId = 1
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(p.Id) > 10 AND SUM(p.Score) > 100
),
BadgeSummary AS (
    SELECT b.UserId, 
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagActivity AS (
    SELECT p.OwnerUserId, tag AS TagName, COUNT(p.Id) AS TagPostCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><') AS tag
    ) AS ttags
    JOIN Tags t ON t.TagName = ttags.tag
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, ttags.tag
),
VoteAnalysis AS (
    SELECT v.PostId, p.OwnerUserId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= '2020-01-01'
    GROUP BY v.PostId, p.OwnerUserId
),
CommentStats AS (
    SELECT c.UserId, COUNT(c.Id) AS CommentCount, AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.CreationDate >= '2020-01-01'
    GROUP BY c.UserId
),
PostHistoryMetrics AS (
    SELECT ph.PostId, p.OwnerUserId, COUNT(ph.Id) AS EditCount,
           MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId, p.OwnerUserId
)
SELECT au.Id AS UserId, au.Reputation, au.PostCount, au.TotalScore,
       COALESCE(bs.GoldBadges,0) AS GoldBadges, COALESCE(bs.SilverBadges,0) AS SilverBadges, COALESCE(bs.BronzeBadges,0) AS BronzeBadges,
       ta.TagName AS TopTag, ta.TagPostCount,
       COALESCE(va.Upvotes, 0) - COALESCE(va.Downvotes, 0) AS NetVotes,
       COALESCE(cs.CommentCount,0) AS CommentCount, cs.AvgCommentScore,
       COALESCE(phm.EditCount,0) AS EditCount, phm.LastEdit,
       RANK() OVER (ORDER BY au.TotalScore DESC) AS ScoreRank
FROM ActiveUsers au
LEFT JOIN BadgeSummary bs ON au.Id = bs.UserId
LEFT JOIN TagActivity ta ON au.Id = ta.OwnerUserId AND ta.TagRank = 1
LEFT JOIN (
    SELECT OwnerUserId, SUM(Upvotes) AS Upvotes, SUM(Downvotes) AS Downvotes
    FROM VoteAnalysis
    GROUP BY OwnerUserId
) va ON au.Id = va.OwnerUserId
LEFT JOIN CommentStats cs ON au.Id = cs.UserId
LEFT JOIN (
    SELECT OwnerUserId, SUM(EditCount) AS EditCount, MAX(LastEdit) AS LastEdit
    FROM PostHistoryMetrics
    GROUP BY OwnerUserId
) phm ON au.Id = phm.OwnerUserId
WHERE COALESCE(bs.GoldBadges,0) > 0 OR COALESCE(ta.TagPostCount,0) > 5
ORDER BY au.TotalScore DESC, au.PostCount DESC
LIMIT 100;