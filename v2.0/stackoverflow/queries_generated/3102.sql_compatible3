WITH
BadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount,
        COUNT(*)                                        AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostStats AS (
    SELECT
        p.OwnerUserId                     AS UserId,
        COUNT(*)                          AS QuestionCount,
        AVG(p.Score)                      AS AvgScore,
        MAX(p.CreationDate)               AS LastQuestionDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY MAX(p.Score) DESC) AS TopScoreRank,
        COALESCE((
            SELECT STRING_AGG(tag, ', ' ORDER BY tag)
            FROM (
                SELECT DISTINCT TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM regexp_split_to_table(p.Tags, '><'))) AS tag
            ) t
        ), '') AS AllTags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.Tags
),
LatestActivity AS (
    SELECT u.Id AS UserId,
           GREATEST(
               COALESCE((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id), DATE '1970-01-01'),
               COALESCE((SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = u.Id), DATE '1970-01-01'),
               COALESCE(u.LastAccessDate, DATE '1970-01-01')
           ) AS LastActivity
    FROM Users u
),
ActiveGoldUsers AS (
    SELECT ba.UserId
    FROM BadgeAgg ba
    JOIN LatestActivity la ON la.UserId = ba.UserId
    WHERE ba.GoldCount > 0
      AND la.LastActivity >= (DATE '2024-10-01' - INTERVAL '180' DAY)
),
HighRepOrBronze AS (
    SELECT u.Id AS UserId
    FROM Users u
    WHERE u.Reputation >= 20000
    UNION
    SELECT ba.UserId
    FROM BadgeAgg ba
    WHERE ba.BronzeCount >= 100
),
FinalUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ps.QuestionCount, 0)          AS QuestionCount,
        COALESCE(ps.AvgScore, 0)               AS AvgQuestionScore,
        COALESCE(ba.GoldCount, 0)              AS GoldBadges,
        COALESCE(ba.SilverCount, 0)            AS SilverBadges,
        COALESCE(ba.BronzeCount, 0)            AS BronzeBadges,
        COALESCE(ps.AllTags, '')               AS TagsUsed,
        la.LastActivity
    FROM Users u
    LEFT JOIN BadgeAgg ba     ON ba.UserId = u.Id
    LEFT JOIN PostStats ps    ON ps.UserId = u.Id
    LEFT JOIN LatestActivity la ON la.UserId = u.Id
    WHERE u.Id IN (SELECT UserId FROM ActiveGoldUsers)
      AND u.Id IN (SELECT UserId FROM HighRepOrBronze)
      AND (u.Location IS NOT NULL AND u.Location <> '')
      AND (u.WebsiteUrl IS NOT NULL OR u.AboutMe IS NOT NULL)
)
SELECT
    fu.Id,
    fu.DisplayName,
    fu.Reputation,
    fu.QuestionCount,
    ROUND(fu.AvgQuestionScore, 2)          AS AvgScoreRounded,
    fu.GoldBadges,
    fu.SilverBadges,
    fu.BronzeBadges,
    fu.TagsUsed,
    fu.LastActivity,
    CASE
        WHEN fu.Reputation >= 50000 THEN 'Legendary'
        WHEN fu.Reputation >= 20000 THEN 'PowerUser'
        WHEN fu.Reputation >= 10000 THEN 'Experienced'
        ELSE 'Contributor'
    END                                    AS ReputationTier,
    COALESCE(NULLIF(fu.TagsUsed, ''), 'No tags recorded') AS TagSummary,
    (SELECT COUNT(*)
       FROM Votes v
       WHERE v.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = fu.Id)
         AND v.VoteTypeId = 2
         AND v.CreationDate >= (DATE '2024-10-01' - INTERVAL '30' DAY)) AS RecentUpVotes
FROM FinalUsers fu
ORDER BY fu.Reputation DESC, fu.GoldBadges DESC, fu.Id
FETCH FIRST 100 ROWS ONLY;