WITH RankedAnswers AS (
    SELECT
        p.Id AS PostId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererUserId,
        p.CreationDate AS AnswerCreationDate,
        p.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2
),
UserAnswerStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        COUNT(DISTINCT ra.PostId) AS TotalAnswers,
        SUM(ra.AnswerScore) AS TotalAnswerScore,
        AVG(
            (CAST(ra.AnswerCreationDate AS DATE) - CAST(u.CreationDate AS DATE))
        ) AS AvgDaysToAnswer,
        MAX(ra.AnswerCreationDate) AS LastAnswerDate
    FROM Users u
    JOIN RankedAnswers ra ON u.Id = ra.AnswererUserId
    GROUP BY u.Id, u.DisplayName
),
QuestionEngagement AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionerUserId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.AnswerCount,
        q.FavoriteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCountOnQuestion,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN q.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        NULLIF(q.Tags, '') AS TagsString
    FROM Posts q
    WHERE q.PostTypeId = 1
),
QuestionMetrics AS (
    SELECT
        qe.QuestionId,
        qe.QuestionTitle,
        qe.QuestionCreationDate,
        qe.QuestionScore,
        qe.AnswerCount,
        qe.FavoriteCount,
        qe.CommentCountOnQuestion,
        qe.DuplicateLinks,
        qe.IsClosed,
        qe.IsCommunityOwned,
        qe.TagsString,
        u.DisplayName AS QuestionerName,
        COALESCE(das.TotalAnswers, 0) AS QuestionerTotalAnswers,
        COALESCE(das.TotalAnswerScore, 0) AS QuestionerTotalAnswerScore,
        CASE WHEN qe.QuestionScore > 100 AND qe.FavoriteCount > 10 THEN 'Highly Engaged'
             WHEN qe.AnswerCount > 10 AND qe.CommentCountOnQuestion > 5 THEN 'Popular'
             WHEN qe.IsClosed = 1 THEN 'Closed'
             WHEN qe.DuplicateLinks > 0 THEN 'Duplicate'
             ELSE 'Standard'
        END AS QuestionCategory,
        NULL AS TagValueHolder
    FROM QuestionEngagement qe
    LEFT JOIN Users u ON qe.QuestionerUserId = u.Id
    LEFT JOIN UserAnswerStats das ON u.Id = das.UserId
)
SELECT
    qm.QuestionId,
    qm.QuestionTitle,
    qm.QuestionCreationDate,
    qm.QuestionScore,
    qm.AnswerCount,
    qm.FavoriteCount,
    qm.CommentCountOnQuestion,
    qm.DuplicateLinks,
    qm.IsClosed,
    qm.IsCommunityOwned,
    qm.QuestionerName,
    qm.QuestionerTotalAnswers,
    qm.QuestionerTotalAnswerScore,
    qm.QuestionCategory,
    (SELECT Name FROM PostTypes WHERE Id = 1 LIMIT 1) AS QuestionPostTypeName,
    'Processed' AS ProcessingStatus,
    CASE
        WHEN qm.QuestionCategory = 'Highly Engaged' AND qm.QuestionScore > qm.AnswerCount * 2 THEN 'High Score per Answer'
        WHEN qm.QuestionCategory = 'Popular' AND qm.FavoriteCount < 5 THEN 'Popular but Less Favored'
        ELSE 'Standard Analysis'
    END AS DerivedMetric,
    CHAR_LENGTH(qm.QuestionTitle) AS TitleLength,
    SUBSTRING(qm.QuestionTitle FROM 1 FOR 10) AS TitlePrefix,
    CASE WHEN qm.QuestionerTotalAnswerScore > 10000 THEN 'Expert' ELSE 'Intermediate' END AS QuestionerExpertise,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = q.OwnerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = q.OwnerUserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = q.OwnerUserId AND b.Class = 3) AS BronzeBadges,
    t.TagName,
    pht.Name AS LastEditType
FROM QuestionMetrics qm
LEFT JOIN (
    SELECT
        QuestionId,
        CASE WHEN part = '' THEN NULL ELSE part END AS TagName
    FROM (
        SELECT
            qe.QuestionId,
            TRIM(value) AS part
        FROM QuestionEngagement qe
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(qe.TagsString, '><') AS value
        ) s
        WHERE qe.TagsString IS NOT NULL
    ) sub
) t ON qm.QuestionId = t.QuestionId
LEFT JOIN PostHistory ph ON qm.QuestionId = ph.PostId AND ph.PostHistoryTypeId = 6
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN Posts q ON qm.QuestionId = q.Id
WHERE qm.QuestionScore > 0
  AND qm.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND qm.QuestionerName IS NOT NULL
GROUP BY
    qm.QuestionId,
    qm.QuestionTitle,
    qm.QuestionCreationDate,
    qm.QuestionScore,
    qm.AnswerCount,
    qm.FavoriteCount,
    qm.CommentCountOnQuestion,
    qm.DuplicateLinks,
    qm.IsClosed,
    qm.IsCommunityOwned,
    qm.QuestionerName,
    qm.QuestionerTotalAnswers,
    qm.QuestionerTotalAnswerScore,
    qm.QuestionCategory,
    qm.TagsString,
    t.TagName,
    pht.Name,
    q.OwnerUserId

HAVING COUNT(t.TagName) > 0

UNION ALL

SELECT
    NULL AS QuestionId,
    'Total Questions Processed' AS QuestionTitle,
    NULL AS QuestionCreationDate,
    NULL AS QuestionScore,
    SUM(AnswerCount) AS AnswerCount,
    NULL AS FavoriteCount,
    NULL AS CommentCountOnQuestion,
    NULL AS DuplicateLinks,
    NULL AS IsClosed,
    NULL AS IsCommunityOwned,
    NULL AS QuestionerName,
    NULL AS QuestionerTotalAnswers,
    NULL AS QuestionerTotalAnswerScore,
    NULL AS QuestionCategory,
    NULL AS QuestionPostTypeName,
    NULL AS ProcessingStatus,
    NULL AS DerivedMetric,
    NULL AS TitleLength,
    NULL AS TitlePrefix,
    NULL AS QuestionerExpertise,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS TagName,
    NULL AS LastEditType
FROM QuestionMetrics
WHERE QuestionScore > 0
  AND QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31';