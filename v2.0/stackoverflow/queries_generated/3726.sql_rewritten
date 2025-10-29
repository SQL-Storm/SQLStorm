-- {"query": "3726.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2577} 
WITH UserPostAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                                     AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)                                     AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                                 AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)                                 AS AvgAnswerScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)            AS AcceptedAnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1)                                         AS GoldBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 2)                                         AS SilverBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 3)                                         AS BronzeBadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1)                AS GoldBadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
UserTagAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><'))                 AS Tag,
        COUNT(*)                                                                     AS TagUseCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
UserTopTag AS (
    SELECT
        t.UserId,
        t.Tag,
        t.TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY t.UserId ORDER BY t.TagUseCount DESC)      AS rn
    FROM UserTagAgg t
),
UserDupInfo AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pl.RelatedPostId)                                            AS DuplicateLinkCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
Combined AS (
    SELECT
        u.Id,
        COALESCE(u.DisplayName, 'Anonymous')                                         AS DisplayName,
        u.Reputation,
        COALESCE(up.QuestionCount, 0)                                                AS QuestionCount,
        COALESCE(up.AnswerCount, 0)                                                  AS AnswerCount,
        COALESCE(up.AvgQuestionScore, 0)                                            AS AvgQuestionScore,
        COALESCE(up.AvgAnswerScore, 0)                                              AS AvgAnswerScore,
        COALESCE(up.AcceptedAnswerCount, 0)                                         AS AcceptedAnswerCount,
        COALESCE(ub.GoldBadgeCount, 0)                                               AS GoldBadgeCount,
        COALESCE(ub.SilverBadgeCount, 0)                                             AS SilverBadgeCount,
        COALESCE(ub.BronzeBadgeCount, 0)                                             AS BronzeBadgeCount,
        ub.GoldBadgeNames,
        COALESCE(ud.DuplicateLinkCount, 0)                                           AS DuplicateLinkCount,
        tt.Tag                                                                       AS TopTag,
        tt.TagUseCount                                                               AS TopTagUseCount,
        CASE
            WHEN u.Location IS NULL AND u.WebsiteUrl IS NOT NULL THEN 'HasWebsiteOnly'
            WHEN u.Location IS NOT NULL AND u.WebsiteUrl IS NULL THEN 'HasLocationOnly'
            WHEN u.Location IS NULL AND u.WebsiteUrl IS NULL THEN 'NoGeoInfo'
            ELSE 'FullInfo'
        END                                                                          AS GeoInfoFlag,
        CONCAT('User_', u.Id)                                                        AS UserKey,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                               AS ReputationRank
    FROM Users u
    LEFT JOIN UserPostAgg up ON up.UserId = u.Id
    LEFT JOIN UserBadgeAgg ub ON ub.UserId = u.Id
    LEFT JOIN UserDupInfo ud ON ud.UserId = u.Id
    LEFT JOIN UserTopTag tt ON tt.UserId = u.Id AND tt.rn = 1
)
SELECT *
FROM Combined
WHERE ReputationRank <= 20
  AND (QuestionCount + AnswerCount) > 10
  AND GoldBadgeCount >= 1

UNION ALL

SELECT
    NULL                                   AS Id,
    'NoPosts'                              AS DisplayName,
    NULL                                   AS Reputation,
    0                                      AS QuestionCount,
    0                                      AS AnswerCount,
    0                                      AS AvgQuestionScore,
    0                                      AS AvgAnswerScore,
    0                                      AS AcceptedAnswerCount,
    COALESCE(b.GoldBadgeCount, 0)          AS GoldBadgeCount,
    COALESCE(b.SilverBadgeCount, 0)        AS SilverBadgeCount,
    COALESCE(b.BronzeBadgeCount, 0)        AS BronzeBadgeCount,
    b.GoldBadgeNames,
    0                                      AS DuplicateLinkCount,
    NULL                                   AS TopTag,
    NULL                                   AS TopTagUseCount,
    'BadgeOnly'                            AS GeoInfoFlag,
    CONCAT('BadgeUser_', COALESCE(b.UserId,0)) AS UserKey,
    NULL                                   AS ReputationRank
FROM UserBadgeAgg b
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = b.UserId)
  AND b.GoldBadgeCount > 0

ORDER BY ReputationRank NULLS LAST, GoldBadgeCount DESC;