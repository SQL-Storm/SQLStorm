WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
           COALESCE(AVG(p.Score) OVER (PARTITION BY u.Id), 0) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate > (TIMESTAMP '2024-10-01 12:34:56') - INTERVAL '1 year'
      AND (u.Reputation > (SELECT AVG(Reputation) FROM Users) OR u.Reputation IS NULL)
),
UserBadges AS (
    SELECT ub.UserId, COUNT(ub.Id) AS BadgeCount,
           STRING_AGG(ub.Name, ', ') AS BadgeNames,
           MAX(CASE WHEN ub.Class = 1 THEN ub.Date ELSE NULL END) AS LatestGoldBadge
    FROM Badges ub
    GROUP BY ub.UserId
    HAVING COUNT(ub.Id) > 5
),
TaggedPosts AS (
    SELECT p.Id AS PostId, p.OwnerUserId,
           (SELECT COUNT(*) 
            FROM (SELECT (regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag) AS t
            WHERE tag ILIKE '%sql%') AS SqlTagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags LIKE '%<sql>%'
),
UserActivity AS (
    SELECT au.Id, au.Reputation, au.DisplayName, au.RepRank, au.AvgPostScore,
           COALESCE(ub.BadgeCount, 0) AS BadgeCount, ub.BadgeNames,
           ub.LatestGoldBadge,
           (SELECT COUNT(*) FROM Comments c WHERE c.UserId = au.Id AND c.Score > 0) AS PositiveComments,
           tp.SqlTagCount,
           CASE WHEN tp.SqlTagCount > 0 THEN 'SQL Expert' ELSE NULLIF('Novice', 'Novice') END AS ExpertiseLevel,
           LAG(au.Reputation) OVER (ORDER BY au.RepRank) AS PrevRep
    FROM ActiveUsers au
    LEFT JOIN UserBadges ub ON au.Id = ub.UserId
    LEFT JOIN TaggedPosts tp ON au.Id = tp.OwnerUserId
    WHERE EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = au.Id AND v.VoteTypeId IN (2, 3))
      OR au.Reputation > 1000
)
SELECT ua.Id, ua.DisplayName, ua.Reputation, ua.RepRank,
       ua.AvgPostScore, ua.BadgeCount, ua.BadgeNames,
       ua.LatestGoldBadge, ua.PositiveComments, ua.SqlTagCount,
       ua.ExpertiseLevel, ua.PrevRep,
       (SELECT SUM(Score) FROM Posts p WHERE p.OwnerUserId = ua.Id AND p.CreationDate > ua.LatestGoldBadge) AS PostScoreAfterGold
FROM UserActivity ua
WHERE ua.BadgeCount > 10
UNION ALL
SELECT ua.Id, CASE WHEN ua.DisplayName IS NOT NULL THEN ua.DisplayName || ' (Low Activity)' ELSE NULL END, ua.Reputation, ua.RepRank,
       ua.AvgPostScore, ua.BadgeCount, ua.BadgeNames,
       ua.LatestGoldBadge, ua.PositiveComments, ua.SqlTagCount,
       ua.ExpertiseLevel, ua.PrevRep,
       (SELECT SUM(Score) FROM Posts p WHERE p.OwnerUserId = ua.Id AND p.CreationDate > ua.LatestGoldBadge) AS PostScoreAfterGold
FROM UserActivity ua
WHERE ua.BadgeCount <= 10 AND ua.PositiveComments < 5
INTERSECT
SELECT ua.Id, ua.DisplayName, ua.Reputation, ua.RepRank,
       ua.AvgPostScore, ua.BadgeCount, ua.BadgeNames,
       ua.LatestGoldBadge, ua.PositiveComments, ua.SqlTagCount,
       ua.ExpertiseLevel, ua.PrevRep,
       (SELECT SUM(Score) FROM Posts p WHERE p.OwnerUserId = ua.Id AND p.CreationDate > ua.LatestGoldBadge) AS PostScoreAfterGold
FROM UserActivity ua
WHERE ua.ExpertiseLevel IS NOT NULL
ORDER BY RepRank;