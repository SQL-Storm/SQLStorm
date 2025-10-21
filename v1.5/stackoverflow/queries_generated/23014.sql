-- {"query": "23014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 784} 

WITH TopUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM Users u
    WHERE u.Reputation > 10000
      AND u.Location IS NOT NULL
      AND LENGTH(u.Location) > 5
    LIMIT 100
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) AS GoldBadges,
           STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS BadgeNames
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
    HAVING COUNT(*) >= 3
),
UserPosts AS (
    SELECT p.OwnerUserId, p.Id AS PostId, p.Score, p.ViewCount, p.Tags,
           COALESCE(p.AnswerCount, 0) AS Answers,
           RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank,
           (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBounty
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%sql%'
      AND p.CreationDate > '2020-01-01'
      AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5)
),
ComplexJoins AS (
    SELECT tu.Id AS UserId, tu.DisplayName, ub.GoldBadges, up.PostId, up.Score, up.ViewCount,
           COALESCE(up.AvgBounty, 0) AS BountyAvg,
           CASE WHEN up.Tags IS NULL THEN 'No Tags' ELSE REPLACE(SUBSTRING(up.Tags, 2, LENGTH(up.Tags)-2), '><', ', ') END AS CleanTags,
           (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = up.PostId AND ph.PostHistoryTypeId IN (4,5,6) AND ph.UserId = tu.Id) AS Edits
    FROM TopUsers tu
    LEFT OUTER JOIN UserBadges ub ON tu.Id = ub.UserId
    INNER JOIN UserPosts up ON tu.Id = up.OwnerUserId AND up.PostRank <= 5
    WHERE tu.Rank <= 50
      AND (ub.GoldBadges IS NULL OR ub.GoldBadges > 1)
),
UnionSet AS (
    SELECT UserId, DisplayName, GoldBadges, PostId, Score, ViewCount, BountyAvg, CleanTags, Edits
    FROM ComplexJoins
    UNION ALL
    SELECT tu.Id, tu.DisplayName, NULL AS GoldBadges, NULL AS PostId, 0 AS Score, 0 AS ViewCount, 0 AS BountyAvg, 'Inactive' AS CleanTags, 0 AS Edits
    FROM TopUsers tu
    LEFT OUTER JOIN Posts p ON tu.Id = p.OwnerUserId
    WHERE p.Id IS NULL
)
SELECT UserId, DisplayName, COALESCE(GoldBadges, 0) AS GoldBadges,
       STRING_AGG(CAST(PostId AS VARCHAR) || ' (' || Score || ')', '; ') OVER (PARTITION BY UserId) AS TopPosts,
       SUM(ViewCount) AS TotalViews,
       AVG(BountyAvg) AS AvgBountyPerUser,
       MAX(Edits) AS MaxEdits,
       CASE WHEN CleanTags LIKE '%database%' THEN 'DB Expert' ELSE 'General' END AS Category
FROM UnionSet
GROUP BY UserId, DisplayName, GoldBadges, CleanTags
HAVING SUM(ViewCount) > 100000
ORDER BY SUM(Score) DESC NULLS LAST;
