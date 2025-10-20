WITH recent_questions AS (
    SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
), answer_stats AS (
    SELECT
        r.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore
    FROM recent_questions r
    JOIN Posts a
      ON a.ParentId = r.Id
     AND a.PostTypeId = 2
    GROUP BY r.Id
), badge_stats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY b.UserId
), tag_exploded AS (
    SELECT
        r.Id AS QuestionId,
        TRIM(tag) AS Tag
    FROM recent_questions r,
    LATERAL (
        SELECT value AS tag
        FROM (
            SELECT UNNEST(string_to_array(SUBSTRING(r.Tags FROM 2 FOR (LENGTH(r.Tags) - 2)), '><')) AS value
        ) s
    ) split
), tag_stats AS (
    SELECT
        te.Tag,
        COUNT(*)                     AS QuestionCount,
        SUM(a.AnswerCount)           AS TotalAnswers,
        AVG(a.AvgAnswerScore)        AS AvgAnswerScore
    FROM tag_exploded te
    JOIN answer_stats a
      ON a.QuestionId = te.QuestionId
    GROUP BY te.Tag
)
SELECT
    u.Id                       AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(bs.GoldBadges,0)  AS GoldBadges,
    COALESCE(bs.SilverBadges,0) AS SilverBadges,
    COALESCE(bs.BronzeBadges,0) AS BronzeBadges,
    COUNT(rq.Id)               AS QuestionsAsked,
    SUM(a2.AnswerCount)        AS AnswersReceived,
    AVG(a2.AvgAnswerScore)     AS AvgResponseQuality,
    tt.Tag                     AS TopTag,
    tt.QuestionCount           AS TopTagQuestionCount,
    tt.TotalAnswers            AS TopTagTotalAnswers,
    tt.AvgAnswerScore          AS TopTagAvgAnswerScore
FROM Users u
LEFT JOIN recent_questions rq
  ON rq.OwnerUserId = u.Id
LEFT JOIN answer_stats a2
  ON a2.QuestionId = rq.Id
LEFT JOIN badge_stats bs
  ON bs.UserId = u.Id
LEFT JOIN LATERAL (
    SELECT
        t.Tag,
        t.QuestionCount,
        t.TotalAnswers,
        t.AvgAnswerScore
    FROM tag_exploded te2
    JOIN tag_stats t
      ON t.Tag = te2.Tag
    WHERE te2.QuestionId IN (
        SELECT Id
          FROM recent_questions
         WHERE OwnerUserId = u.Id
    )
    ORDER BY t.QuestionCount DESC
    LIMIT 1
) tt ON true
GROUP BY
    u.Id, u.DisplayName, u.Reputation,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
    tt.Tag, tt.QuestionCount, tt.TotalAnswers, tt.AvgAnswerScore
ORDER BY u.Reputation DESC
LIMIT 100;