-- {"query": "39012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3215} 
WITH QuestionTags AS (
    SELECT
        p.Id          AS QuestionId,
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        )             AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        qt.Tag,
        a.OwnerUserId                                                 AS UserId,
        COUNT(*)                                                      AS AnswerCount,
        SUM(a.Score)                                                  AS AnswerScore,
        AVG(
            EXTRACT(
                EPOCH FROM (a.CreationDate - q.CreationDate)
            ) / 3600
        )                                                             AS AvgAnswerDelayHours
    FROM Posts a
    JOIN QuestionTags qt
      ON qt.QuestionId = a.ParentId
    JOIN Posts q
      ON q.Id          = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY qt.Tag, a.OwnerUserId
),
TopAnswerers AS (
    SELECT
        Tag,
        UserId,
        AnswerCount,
        AnswerScore,
        AvgAnswerDelayHours,
        ROW_NUMBER() OVER (
            PARTITION BY Tag
            ORDER BY AnswerScore DESC, AnswerCount DESC
        )                                                            AS RN
    FROM AnswerStats
),
BadgeSummary AS (
    SELECT
        UserId,
        COUNT(*)                                                    AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END)                  AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END)                  AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END)                  AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
CommentSummary AS (
    SELECT
        UserId,
        COUNT(*)                                                    AS TotalComments,
        SUM(Score)                                                  AS CommentScore
    FROM Comments
    GROUP BY UserId
),
UserProfiles AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(bs.TotalBadges, 0)                                 AS TotalBadges,
        COALESCE(bs.GoldBadges, 0)                                  AS GoldBadges,
        COALESCE(bs.SilverBadges, 0)                                AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0)                                AS BronzeBadges,
        COALESCE(cs.TotalComments, 0)                               AS TotalComments,
        COALESCE(cs.CommentScore, 0)                                AS CommentScore
    FROM Users u
    LEFT JOIN BadgeSummary bs
      ON bs.UserId     = u.Id
    LEFT JOIN CommentSummary cs
      ON cs.UserId     = u.Id
)
SELECT
    ta.Tag,
    up.DisplayName,
    up.Reputation,
    ta.AnswerCount,
    ta.AnswerScore,
    ROUND(ta.AvgAnswerDelayHours, 2)                               AS AvgAnswerDelayHours,
    up.TotalBadges,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.TotalComments,
    up.CommentScore
FROM TopAnswerers ta
JOIN UserProfiles up USING (UserId)
WHERE ta.RN <= 3
ORDER BY ta.Tag, ta.RN;