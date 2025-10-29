-- {"query": "4235.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1564} 

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
        AVG(DATEDIFF(day, u.CreationDate, ra.AnswerCreationDate)) AS AvgDaysToAnswer,
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
        STRING_SPLIT(qe.TagsString, '><') AS TagList -- Assuming SQL Server's STRING_SPLIT, adjust if needed
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
    (SELECT TOP 1 Name FROM PostTypes WHERE Id = 1) AS QuestionPostTypeName,
    'Processed' AS ProcessingStatus,
    CASE
        WHEN qm.QuestionCategory = 'Highly Engaged' AND qm.QuestionScore > qm.AnswerCount * 2 THEN 'High Score per Answer'
        WHEN qm.QuestionCategory = 'Popular' AND qm.FavoriteCount < 5 THEN 'Popular but Less Favored'
        ELSE 'Standard Analysis'
    END AS DerivedMetric,
    LEN(qm.QuestionTitle) AS TitleLength,
    SUBSTRING(qm.QuestionTitle, 1, 10) AS TitlePrefix,
    CASE WHEN qm.QuestionerTotalAnswerScore > 10000 THEN 'Expert' ELSE 'Intermediate' END AS QuestionerExpertise,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = qm.QuestionerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = qm.QuestionerUserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = qm.QuestionerUserId AND b.Class = 3) AS BronzeBadges,
    t.TagName,
    pht.Name AS LastEditType
FROM QuestionMetrics qm
LEFT JOIN Tags t ON t.TagName = ANY(SELECT value FROM STRING_SPLIT(qm.TagsString, '><')) -- Lateral join with string split
LEFT JOIN PostHistory ph ON qm.QuestionId = ph.PostId AND ph.PostHistoryTypeId = 6 -- Example: last tag edit type
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
WHERE qm.QuestionScore > 0
  AND qm.QuestionCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
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
    pht.Name
HAVING COUNT(t.TagName) > 0 -- Ensure at least one tag is matched
UNION ALL
SELECT
    NULL, 'Total Questions Processed', NULL, NULL, SUM(AnswerCount), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM QuestionMetrics
WHERE QuestionScore > 0
  AND QuestionCreationDate BETWEEN '2023-01-01' AND '2023-12-31';
