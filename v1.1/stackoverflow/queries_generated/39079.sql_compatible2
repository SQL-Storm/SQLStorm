WITH
RecentQuestions AS (
    SELECT
        p.Id           AS QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
),
TagExplode AS (
    SELECT
        rq.QuestionId,
        rq.OwnerUserId,
        rq.CreationDate    AS QuestionDate,
        tag.TagName
    FROM RecentQuestions rq
    CROSS JOIN LATERAL
        unnest(
            string_to_array(
                substring(COALESCE(rq.Tags, ''), 2, GREATEST(length(COALESCE(rq.Tags, '')) - 2, 0)),
                '><'
            )
        ) AS tag(TagName)
),
FirstAnswers AS (
    SELECT
        p.ParentId    AS QuestionId,
        MIN(p.CreationDate) AS FirstAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
TagAggregates AS (
    SELECT
        te.TagName,
        COUNT(DISTINCT te.QuestionId)                      AS QuestionCount,
        ROUND(
          AVG(
            EXTRACT(
              EPOCH FROM (fa.FirstAnswerDate - te.QuestionDate)
            )
          )/3600
        ,2)                                               AS AvgResponseHours
    FROM TagExplode te
    LEFT JOIN FirstAnswers fa
      ON fa.QuestionId = te.QuestionId
    GROUP BY te.TagName
),
TopTags AS (
    SELECT TagName
    FROM TagAggregates
    ORDER BY QuestionCount DESC
    LIMIT 10
),
UserTagActivity AS (
    SELECT
        p.OwnerUserId         AS UserId,
        te.TagName,
        COUNT(*)              AS AnswersCount
    FROM Posts p
    JOIN TagExplode te
      ON p.ParentId = te.QuestionId
     AND p.PostTypeId = 2
    GROUP BY p.OwnerUserId, te.TagName
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopUsersPerTag AS (
    SELECT
        tt.TagName,
        ta.QuestionCount,
        ta.AvgResponseHours,
        uta.UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ubc.GoldBadges,   0) AS GoldBadges,
        COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
        uta.AnswersCount,
        RANK() OVER (
          PARTITION BY tt.TagName
          ORDER BY uta.AnswersCount DESC
        ) AS UserRank
    FROM TopTags tt
    JOIN TagAggregates ta
      ON ta.TagName = tt.TagName
    LEFT JOIN UserTagActivity uta
      ON uta.TagName = tt.TagName
    LEFT JOIN Users u
      ON u.Id = uta.UserId
    LEFT JOIN UserBadgeCounts ubc
      ON ubc.UserId = u.Id
    WHERE uta.AnswersCount IS NOT NULL
)
SELECT
    TagName,
    QuestionCount,
    AvgResponseHours,
    UserId,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AnswersCount,
    UserRank
FROM TopUsersPerTag
WHERE UserRank <= 3
ORDER BY QuestionCount DESC, UserRank;