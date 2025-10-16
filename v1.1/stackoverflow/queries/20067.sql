-- {"query": "20067.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1602} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 AND u.DisplayName IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
AnswerDetails AS (
    SELECT
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        q.AcceptedAnswerId,
        q.Tags AS QuestionTags,
        q.CreationDate AS QuestionCreationDate,
        DENSE_RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
),
UserAnswerPerformance AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS TotalAnswers,
        SUM(CASE WHEN AnswerId = AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers,
        SUM(CASE WHEN AnswerRank = 1 THEN 1 ELSE 0 END) AS TopRankedAnswers,
        AVG(AnswerScore) AS AvgAnswerScore,
        AVG(EXTRACT(EPOCH FROM (AnswerCreationDate - QuestionCreationDate))) / 3600.0 AS AvgHoursToAnswer
    FROM AnswerDetails
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserTagFocus AS (
    SELECT
        OwnerUserId,
        TagName,
        TagCount,
        AvgTagScore
    FROM (
        SELECT
            ad.OwnerUserId,
            t.TagName,
            COUNT(*) AS TagCount,
            AVG(ad.AnswerScore) AS AvgTagScore,
            ROW_NUMBER() OVER (PARTITION BY ad.OwnerUserId ORDER BY COUNT(*) DESC, AVG(ad.AnswerScore) DESC) as rn
        FROM AnswerDetails ad,
             unnest(string_to_array(substring(ad.QuestionTags, 2, length(ad.QuestionTags)-2), '><')) AS t(TagName)
        WHERE ad.OwnerUserId IS NOT NULL AND ad.QuestionTags IS NOT NULL
        GROUP BY ad.OwnerUserId, t.TagName
    ) AS TagRanking
    WHERE rn = 1
),
NotableUsers AS (
    SELECT
      u.Id,
      'High Reputation (>200k)' as Reason
    FROM Users u
    WHERE u.Reputation > 200000 AND u.Id IN (SELECT UserId FROM UserActivitySummary WHERE TotalQuestions > 50)
    UNION
    SELECT
      b.UserId,
      'Rare Gold Badge (' || b.Name || ')' as Reason
    FROM Badges b
    WHERE b.Class = 1 AND b.TagBased = '0' AND b.Name NOT IN ('Fanatic', 'Legendary', 'Strunk & White', 'Great Answer', 'Great Question', 'Famous Question')
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalQuestions,
    COALESCE(uap.TotalAnswers, 0) as TotalAnswers,
    COALESCE(CAST(uap.AcceptedAnswers AS REAL) / NULLIF(uap.TotalAnswers, 0), 0) * 100 AS PctAccepted,
    uap.AvgAnswerScore,
    uap.AvgHoursToAnswer,
    utf.TagName AS PrimaryTag,
    utf.TagCount AS PrimaryTagAnswers,
    utf.AvgTagScore AS PrimaryTagAvgScore,
    (
        LOG(GREATEST(1, uas.Reputation)) * 10 +
        uas.GoldBadges * 100 +
        uas.SilverBadges * 25 +
        uas.BronzeBadges * 5 +
        COALESCE(uap.AcceptedAnswers, 0) * 20 +
        COALESCE(uap.TopRankedAnswers, 0) * 10 -
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.Score < 0) * 5
    ) / (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - uas.CreationDate))/(3600*24*365.25) + 1) AS NormalizedInfluenceScore,
    CASE
        WHEN nu.Id IS NOT NULL THEN 'Yes: ' || nu.Reason
        ELSE 'No'
    END AS IsNotable,
    DENSE_RANK() OVER (ORDER BY (
        LOG(GREATEST(1, uas.Reputation)) * 10 +
        uas.GoldBadges * 100 +
        uas.SilverBadges * 25 +
        uas.BronzeBadges * 5 +
        COALESCE(uap.AcceptedAnswers, 0) * 20 +
        COALESCE(uap.TopRankedAnswers, 0) * 10 -
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = uas.UserId AND p.Score < 0) * 5
    ) / (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - uas.CreationDate))/(3600*24*365.25) + 1) DESC NULLS LAST) AS InfluenceRank
FROM
    UserActivitySummary uas
LEFT JOIN
    UserAnswerPerformance uap ON uas.UserId = uap.OwnerUserId
LEFT JOIN
    UserTagFocus utf ON uas.UserId = utf.OwnerUserId
LEFT JOIN
    NotableUsers nu ON uas.UserId = nu.Id
WHERE
    uas.Reputation > 1000
    AND uas.CreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 year')
    AND (uap.TotalAnswers > 25 OR uas.GoldBadges > 0)
    AND uas.DisplayName ~ '^[a-zA-Z0-9\s.-]+$'
    AND EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.UserId = uas.UserId
          AND c.Score > 5
          AND c.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
    )
ORDER BY
    InfluenceRank ASC, uas.Reputation DESC
LIMIT 250;