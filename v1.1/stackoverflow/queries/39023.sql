WITH ParsedTags AS (
    SELECT
        p.Id           AS QuestionId,
        lower(tagged.tg) AS Tag
    FROM Posts p
    CROSS JOIN LATERAL
        unnest(
            string_to_array(
                substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)),
                '><'
            )
        ) AS tagged(tg)
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        pt.Tag,
        COUNT(a.Id)                                  AS TotalAnswers,
        AVG(a.Score)                                 AS AvgAnswerScore,
        AVG(
            EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0
        )                                            AS AvgAnswerLagHours
    FROM ParsedTags pt
    JOIN Posts q
        ON q.Id = pt.QuestionId
    JOIN Posts a
        ON a.ParentId = q.Id
       AND a.PostTypeId = 2
    GROUP BY pt.Tag
),
UserBadges AS (
    SELECT
        u.Id                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id)            AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b
        ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopAnswerers AS (
    SELECT
        pt.Tag,
        a.OwnerUserId                           AS UserId,
        COUNT(*)                                AS AnswersCount,
        SUM(a.Score)                            AS AnswersScore,
        ROW_NUMBER() OVER (
            PARTITION BY pt.Tag
            ORDER BY COUNT(*) DESC, SUM(a.Score) DESC
        )                                       AS rn
    FROM ParsedTags pt
    JOIN Posts a
        ON a.ParentId = pt.QuestionId
       AND a.PostTypeId = 2
       AND a.OwnerUserId > 0
    GROUP BY pt.Tag, a.OwnerUserId
),
TopAnswererInfo AS (
    SELECT
        ta.Tag,
        ta.UserId,
        ta.AnswersCount,
        ta.AnswersScore,
        ub.DisplayName     AS TopUserName,
        ub.Reputation      AS TopUserReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges
    FROM TopAnswerers ta
    JOIN UserBadges ub
        ON ub.UserId = ta.UserId
    WHERE ta.rn = 1
)
SELECT
    es.Tag                                         AS TagName,
    es.TotalAnswers,
    ROUND(es.AvgAnswerScore, 2)                    AS AvgAnswerScore,
    ROUND(es.AvgAnswerLagHours, 2)                 AS AvgAnswerLagHrs,
    tai.TopUserName                                AS TopAnswerer,
    tai.TopUserReputation,
    tai.AnswersCount,
    tai.AnswersScore,
    tai.GoldBadges,
    tai.SilverBadges,
    tai.BronzeBadges
FROM AnswerStats es
LEFT JOIN TopAnswererInfo tai
    ON tai.Tag = es.Tag
ORDER BY es.TotalAnswers DESC, es.AvgAnswerScore DESC
LIMIT 50;