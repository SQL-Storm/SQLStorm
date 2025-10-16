WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(u.Location, 'Unknown') AS UserLocation,
           COUNT(b.Id) AS BadgeCount,
           u.CreationDate
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND (u.AboutMe IS NOT NULL OR u.WebsiteUrl IS NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
    HAVING COUNT(b.Id) > 5
),
QuestionStats AS (
    SELECT p.Id AS PostId, p.Title, p.ViewCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           STRING_AGG(t.tag, ', ') AS TagList
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.Score > 10
    GROUP BY p.Id, p.Title, p.ViewCount
    HAVING SUM(CASE WHEN p.ClosedDate IS NULL THEN 1 ELSE 0 END) > 0
),
CombinedData AS (
    SELECT tu.Id, tu.DisplayName, tu.Reputation, tu.UserRank, tu.UserLocation, tu.BadgeCount, tu.CreationDate,
           qs.PostId, qs.Title, qs.ViewCount, qs.PositiveComments, qs.TagList,
           RANK() OVER (PARTITION BY tu.Id ORDER BY qs.ViewCount DESC) AS QuestionRank,
           NULLIF(qs.ViewCount / NULLIF(tu.Reputation, 0), 0) AS ViewPerRep
    FROM TopUsers tu
    INNER JOIN Posts p ON tu.Id = p.OwnerUserId
    LEFT OUTER JOIN QuestionStats qs ON p.Id = qs.PostId
    WHERE EXISTS (
        SELECT 1 FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
          AND v.CreationDate > tu.CreationDate
    )
    UNION ALL
    SELECT tu.Id, tu.DisplayName, tu.Reputation, tu.UserRank, tu.UserLocation, tu.BadgeCount, tu.CreationDate,
           NULL AS PostId, NULL AS Title, 0 AS ViewCount, 0 AS PositiveComments, '' AS TagList,
           0 AS QuestionRank, 0 AS ViewPerRep
    FROM TopUsers tu
    WHERE NOT EXISTS (
        SELECT 1 FROM Posts p WHERE tu.Id = p.OwnerUserId AND p.PostTypeId = 1
    )
)
SELECT cd.DisplayName, cd.Reputation, cd.UserRank, cd.BadgeCount, cd.UserLocation,
       cd.Title, cd.ViewCount, cd.PositiveComments, cd.TagList,
       CASE WHEN cd.QuestionRank = 1 THEN 'Top Question' ELSE 'Other' END AS RankCategory,
       AVG(cd.ViewPerRep) OVER (PARTITION BY cd.UserRank) AS AvgViewPerRep
FROM CombinedData cd
LEFT OUTER JOIN PostHistory ph ON cd.PostId = ph.PostId AND ph.PostHistoryTypeId = 5
WHERE cd.ViewCount > 10000 OR cd.BadgeCount > 10
GROUP BY cd.DisplayName, cd.Reputation, cd.UserRank, cd.BadgeCount, cd.UserLocation,
         cd.Title, cd.ViewCount, cd.PositiveComments, cd.TagList, cd.QuestionRank, cd.ViewPerRep
ORDER BY cd.UserRank ASC, cd.QuestionRank ASC
FETCH FIRST 100 ROWS ONLY;