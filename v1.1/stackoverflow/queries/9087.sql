WITH
FilteredPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        (SELECT COUNT(*) 
           FROM Posts ans
          WHERE ans.ParentId = p.Id
            AND ans.Score > p.Score / NULLIF(NULLIF(ABS(p.Score),0),1)
        ) AS BetterAnswers,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.Score DESC, p.CreationDate DESC
        ) AS UserRank,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
      AND p.Tags ILIKE '%<sql>%'
),
BadgesPerUser AS (
    SELECT
        b.UserId,
        COUNT(*)                         AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date > CAST('2024-10-01' AS DATE) - INTERVAL '6 months'
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT
        u.Id             AS UserId,
        u.DisplayName,
        u.CreationDate,
        COALESCE(bp.TotalBadges, 0)  AS TotalBadges,
        COALESCE(bp.GoldBadges,  0)  AS GoldBadges,
        COALESCE(bp.SilverBadges,0)  AS SilverBadges,
        COALESCE(bp.BronzeBadges,0)  AS BronzeBadges,
        COUNT(DISTINCT p.Id)         AS QuestionCount,
        SUM(COALESCE(p.Score,0))     AS TotalQuestionScore,
        COUNT(c.Id) FILTER (
            WHERE c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
        )                            AS RecentComments
    FROM Users u
    LEFT JOIN BadgesPerUser bp ON bp.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY
        u.Id, u.DisplayName, u.CreationDate,
        bp.TotalBadges, bp.GoldBadges, bp.SilverBadges, bp.BronzeBadges
),
TopActiveUsers AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.CreationDate,
        ua.TotalBadges,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionCount,
        ua.TotalQuestionScore,
        ua.RecentComments,
        RANK() OVER (
            ORDER BY
              ua.TotalBadges   DESC,
              ua.QuestionCount DESC,
              ua.TotalQuestionScore DESC
        ) AS ActivityRank
    FROM UserActivity ua
)
(
    SELECT
        ta.UserId,
        ta.DisplayName,
        ta.CreationDate,
        ta.ActivityRank,
        ta.TotalBadges,
        ta.GoldBadges,
        ta.SilverBadges,
        ta.BronzeBadges,
        ta.QuestionCount,
        ta.TotalQuestionScore,
        ta.RecentComments,
        fp.Id            AS TopQuestionId,
        fp.Title         AS TopQuestionTitle,
        fp.Score         AS TopQuestionScore,
        (
          SELECT STRING_AGG(tag, ', ')
          FROM (
            SELECT unnest(string_to_array(substring(fp.Tags FROM 2 FOR length(fp.Tags)-2), '><')) AS tag
          ) t
        )                AS TopQuestionTags
    FROM TopActiveUsers ta
    LEFT JOIN FilteredPosts fp
      ON fp.OwnerUserId = ta.UserId
     AND fp.UserRank = 1
    WHERE ta.ActivityRank <= 100
)
UNION ALL
(
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        u.CreationDate,
        CAST(NULL AS INTEGER)      AS ActivityRank,
        0              AS TotalBadges,
        0              AS GoldBadges,
        0              AS SilverBadges,
        0              AS BronzeBadges,
        0              AS QuestionCount,
        0              AS TotalQuestionScore,
        0              AS RecentComments,
        CAST(NULL AS INTEGER)      AS TopQuestionId,
        CAST(NULL AS VARCHAR)      AS TopQuestionTitle,
        CAST(NULL AS INTEGER)      AS TopQuestionScore,
        CAST(NULL AS TEXT)         AS TopQuestionTags
    FROM Users u
    WHERE u.Reputation > 10000
      AND NOT EXISTS (
          SELECT 1
            FROM TopActiveUsers ta
           WHERE ta.UserId = u.Id
      )
)
EXCEPT
(
    SELECT
        ta.UserId,
        ta.DisplayName,
        ta.CreationDate,
        ta.ActivityRank,
        ta.TotalBadges,
        ta.GoldBadges,
        ta.SilverBadges,
        ta.BronzeBadges,
        ta.QuestionCount,
        ta.TotalQuestionScore,
        ta.RecentComments,
        fp.Id,
        fp.Title,
        fp.Score,
        (
          SELECT STRING_AGG(tag, ', ')
          FROM (
            SELECT unnest(string_to_array(substring(fp.Tags FROM 2 FOR length(fp.Tags)-2), '><')) AS tag
          ) t
        )
    FROM TopActiveUsers ta
    LEFT JOIN FilteredPosts fp
      ON fp.OwnerUserId = ta.UserId
     AND fp.UserRank = 1
    WHERE ta.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
)
ORDER BY ActivityRank NULLS LAST, TotalBadges DESC, UserId;