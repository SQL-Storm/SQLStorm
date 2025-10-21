-- {"query": "39039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2543} 

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
        SUM((b.Class = 1)::int)                AS GoldBadges,
        SUM((b.Class = 2)::int)                AS SilverBadges,
        SUM((b.Class = 3)::int)                AS BronzeBadges
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
