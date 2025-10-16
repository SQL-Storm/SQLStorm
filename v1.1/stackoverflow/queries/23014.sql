WITH TopUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS "Rank"
    FROM Users u
    WHERE u.Reputation > 10000
      AND u.Location IS NOT NULL
      AND LENGTH(u.Location) > 5
    -- LIMIT is not standard inside CTE for all dialects; keep but some DBs ignore it in CTEs
    -- If dialect does not support LIMIT here, apply in a wrapping query.
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
      AND p.CreationDate > DATE '2020-01-01'
      AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5)
),
ComplexJoins AS (
    SELECT tu.Id AS UserId, tu.DisplayName, ub.GoldBadges, up.PostId, up.Score, up.ViewCount,
           COALESCE(up.AvgBounty, 0) AS BountyAvg,
           CASE WHEN up.Tags IS NULL THEN 'No Tags'
                ELSE REPLACE(SUBSTRING(up.Tags FROM 2 FOR (CHAR_LENGTH(up.Tags) - 2)), '><', ', ')
           END AS CleanTags,
           (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = up.PostId AND ph.PostHistoryTypeId IN (4,5,6) AND ph.UserId = tu.Id) AS Edits
    FROM TopUsers tu
    LEFT JOIN UserBadges ub ON tu.Id = ub.UserId
    INNER JOIN UserPosts up ON tu.Id = up.OwnerUserId AND up.PostRank <= 5
    WHERE tu."Rank" <= 50
      AND (ub.GoldBadges IS NULL OR ub.GoldBadges > 1)
),
UnionSet AS (
    SELECT UserId, DisplayName, GoldBadges, PostId, Score, ViewCount, BountyAvg, CleanTags, Edits
    FROM ComplexJoins
    UNION ALL
    SELECT tu.Id AS UserId, tu.DisplayName, NULL AS GoldBadges, NULL AS PostId, 0 AS Score, 0 AS ViewCount, 0 AS BountyAvg, 'Inactive' AS CleanTags, 0 AS Edits
    FROM TopUsers tu
    LEFT JOIN Posts p ON tu.Id = p.OwnerUserId
    WHERE p.Id IS NULL
)
SELECT
    u.UserId,
    u.DisplayName,
    COALESCE(u.GoldBadges, 0) AS GoldBadges,
    (SELECT STRING_AGG(t.post_desc, '; ' ORDER BY t.post_desc)
     FROM (
       SELECT CAST(us.PostId AS VARCHAR) || ' (' || CAST(us.Score AS VARCHAR) AS post_desc,
              us.UserId
       FROM UnionSet us
       WHERE us.PostId IS NOT NULL
     ) AS t(post_desc, UserId)
     WHERE t.UserId = u.UserId
    ) AS TopPosts,
    SUM(u.ViewCount) AS TotalViews,
    AVG(u.BountyAvg) AS AvgBountyPerUser,
    MAX(u.Edits) AS MaxEdits,
    CASE WHEN u.CleanTags LIKE '%database%' THEN 'DB Expert' ELSE 'General' END AS Category
FROM UnionSet u
GROUP BY u.UserId, u.DisplayName, u.GoldBadges, u.CleanTags
HAVING SUM(u.ViewCount) > 100000
ORDER BY SUM(u.Score) DESC NULLS LAST;