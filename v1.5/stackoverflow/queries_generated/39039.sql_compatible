WITH TagQuestionStats AS (
    SELECT
        tag AS TagName,
        COUNT(*)                             AS QuestionCount,
        AVG(p.Score)                         AS AvgQuestionScore,
        SUM(p.ViewCount)                     AS TotalViews
    FROM Posts p
    CROSS JOIN LATERAL
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS tag
    WHERE p.PostTypeId = 1
    GROUP BY tag
),
AnswerRankings AS (
    SELECT
        a.ParentId                             AS QuestionId,
        a.Id                                   AS AnswerId,
        a.OwnerUserId                          AS AnswerOwnerUserId,
        a.Score                                AS AnswerScore,
        RANK() OVER (
            PARTITION BY a.ParentId
            ORDER BY a.Score DESC, a.CreationDate
        )                                      AS RankByScore
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswers AS (
    SELECT
        QuestionId,
        AnswerId,
        AnswerOwnerUserId,
        AnswerScore
    FROM AnswerRankings
    WHERE RankByScore = 1
),
UserBadgeCounts AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName                          AS UserName,
        COUNT(b.Id)                            AS BadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)                AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)                AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)                AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b
      ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    tq.TagName,
    tq.QuestionCount,
    tq.AvgQuestionScore,
    tq.TotalViews,
    ta.AnswerId,
    ta.AnswerOwnerUserId      AS TopAnswerUserId,
    ta.AnswerScore            AS TopAnswerScore,
    ub.UserName               AS TopAnswerUserName,
    ub.BadgesEarned,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges
FROM TagQuestionStats tq
JOIN (
    SELECT
        p.Id       AS QuestionId,
        tag        AS TagName
    FROM Posts p
    CROSS JOIN LATERAL
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS tag
    WHERE p.PostTypeId = 1
) pq
  ON pq.TagName = tq.TagName
JOIN TopAnswers ta
  ON ta.QuestionId = pq.QuestionId
JOIN UserBadgeCounts ub
  ON ub.UserId = ta.AnswerOwnerUserId
ORDER BY
    tq.TotalViews DESC,
    tq.AvgQuestionScore DESC
LIMIT 10;