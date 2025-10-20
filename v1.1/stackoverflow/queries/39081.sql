WITH
QuestionTags AS (
    SELECT
        p.Id AS QuestionId,
        u.Id AS OwnerId,
        u.DisplayName AS OwnerName,
        tag_list.tag AS tag
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tag
    ) AS tag_list(tag)
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
RecentAnswers AS (
    SELECT
        a.Id         AS AnswerId,
        a.ParentId   AS QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
      AND a.Score > 0
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    GROUP BY b.UserId
),
UserTagStats AS (
    SELECT
        qt.OwnerId         AS UserId,
        qt.OwnerName       AS UserName,
        qt.tag             AS Tag,
        COUNT(DISTINCT qt.QuestionId)              AS QuestionsAsked,
        COUNT(DISTINCT ra.AnswerId)                AS AnswersGiven,
        AVG(ra.Score)                              AS AvgAnswerScore,
        CAST(MIN(EXTRACT(EPOCH FROM (ra.CreationDate - q.CreationDate))) AS bigint) AS MinResponseSeconds,
        CAST(MAX(EXTRACT(EPOCH FROM (ra.CreationDate - q.CreationDate))) AS bigint) AS MaxResponseSeconds
    FROM QuestionTags qt
    JOIN Posts q
      ON qt.QuestionId = q.Id
    LEFT JOIN RecentAnswers ra
      ON qt.QuestionId = ra.QuestionId
    GROUP BY qt.OwnerId, qt.OwnerName, qt.tag
),
RankedTagStats AS (
    SELECT
        uts.*,
        ROW_NUMBER() OVER (PARTITION BY uts.UserId ORDER BY uts.AnswersGiven DESC NULLS LAST, uts.QuestionsAsked DESC) AS TagRank
    FROM UserTagStats uts
)
SELECT
    u.Id                 AS UserId,
    u.DisplayName        AS UserName,
    u.Reputation,
    COALESCE(ub.GoldBadges, 0)   AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    rts.Tag,
    rts.QuestionsAsked,
    rts.AnswersGiven,
    ROUND(CAST(rts.AvgAnswerScore AS numeric), 2)        AS AvgAnswerScore,
    -- format seconds into days hh:mm:ss using standard SQL functions
    (
      CAST((rts.MinResponseSeconds / 86400) AS varchar) || ' days ' ||
      LPAD(CAST((rts.MinResponseSeconds % 86400) / 3600 AS varchar),2,'0') || ':' ||
      LPAD(CAST((rts.MinResponseSeconds % 3600) / 60 AS varchar),2,'0') || ':' ||
      LPAD(CAST((rts.MinResponseSeconds % 60) AS varchar),2,'0')
    ) AS FastestResponse,
    (
      CAST((rts.MaxResponseSeconds / 86400) AS varchar) || ' days ' ||
      LPAD(CAST((rts.MaxResponseSeconds % 86400) / 3600 AS varchar),2,'0') || ':' ||
      LPAD(CAST((rts.MaxResponseSeconds % 3600) / 60 AS varchar),2,'0') || ':' ||
      LPAD(CAST((rts.MaxResponseSeconds % 60) AS varchar),2,'0')
    ) AS SlowestResponse
FROM RankedTagStats rts
JOIN Users u
  ON rts.UserId = u.Id
LEFT JOIN UserBadges ub
  ON rts.UserId = ub.UserId
WHERE rts.TagRank <= 3
  AND u.Reputation >= 1000
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    rts.Tag,
    rts.QuestionsAsked,
    rts.AnswersGiven,
    rts.AvgAnswerScore,
    rts.MinResponseSeconds,
    rts.MaxResponseSeconds,
    rts.UserId,
    rts.UserName,
    rts.TagRank
ORDER BY u.Reputation DESC, rts.AnswersGiven DESC
LIMIT 50;