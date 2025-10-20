WITH
RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        u.DisplayName AS OwnerName,
        p.OwnerUserId,
        ROW_NUMBER() OVER (
            PARTITION BY DATE_TRUNC('day', p.CreationDate)
            ORDER BY p.Score DESC
        ) AS DailyRank,
        p.Tags
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TopAnswers AS (
    SELECT
        a.ParentId AS QuestionId,
        a.Id       AS AnswerId,
        a.Score    AS AnswerScore,
        RANK() OVER (
            PARTITION BY a.ParentId
            ORDER BY a.Score DESC
        ) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TagAggregation AS (
    SELECT
        t.TagName,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)      AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)      AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)  AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)  AS AvgAnswerScore
    FROM Posts p
    CROSS JOIN LATERAL
        (SELECT UNNEST(
            STRING_TO_ARRAY(
                SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2),
                '><'
            )
        ) AS tag) AS taglist
    JOIN Tags t
      ON t.TagName = taglist.tag
    GROUP BY t.TagName
),
UserMetrics AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS ACount,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END)                                    AS TotalVotes
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v
      ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
BadgeRanks AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (
            ORDER BY COUNT(*) FILTER (WHERE Class = 1) DESC
        ) AS TopGoldRank
    FROM Badges
    GROUP BY UserId
)
SELECT
    rq.Id,
    rq.Title,
    rq.CreationDate,
    rq.Score       AS QuestionScore,
    rq.DailyRank,
    ta.AnswerId,
    ta.AnswerScore,
    ta.AnswerRank,
    tagAgg.TagName,
    tagAgg.QuestionCount,
    tagAgg.AnswerCount,
    tagAgg.AvgQuestionScore,
    tagAgg.AvgAnswerScore,
    um.QCount,
    um.ACount,
    um.TotalVotes,
    br.GoldBadges,
    br.SilverBadges,
    br.BronzeBadges,
    br.TopGoldRank
FROM RecentQuestions rq
LEFT JOIN TopAnswers ta
  ON ta.QuestionId = rq.Id
 AND ta.AnswerRank = 1
LEFT JOIN LATERAL (
    SELECT tg.*
    FROM TagAggregation tg
    WHERE tg.TagName = ANY(
        STRING_TO_ARRAY(
            SUBSTR(rq.Tags, 2, LENGTH(rq.Tags) - 2),
            '><'
        )
    )
    ORDER BY tg.QuestionCount DESC
    LIMIT 1
) tagAgg ON TRUE
LEFT JOIN UserMetrics um
  ON um.Id = rq.OwnerUserId
LEFT JOIN BadgeRanks br
  ON br.UserId = rq.OwnerUserId
ORDER BY rq.CreationDate DESC, rq.Score DESC
LIMIT 100;