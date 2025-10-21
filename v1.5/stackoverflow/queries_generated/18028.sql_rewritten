-- {"query": "18028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1531} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditCounts AS (
    SELECT
        PostId,
        COUNT(*) AS TotalEdits
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
),
QuestionAnswers AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId AS QuestionOwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId
),
UserPostSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(u.Reputation) AS MaxReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
)
SELECT
    qa.QuestionId,
    qa.QuestionTitle,
    COALESCE(owner.DisplayName, 'Community') AS QuestionOwner,
    qa.AnswerCount,
    qa.AcceptedAnswerCount,
    pec.TotalEdits AS PostTotalEdits,
    rpe.EditorDisplayName AS LastEditorDisplayName,
    rpe.EditDate AS LastEditDate,
    CASE
        WHEN qa.AcceptedAnswerCount = 0 AND qa.AnswerCount > 0 THEN 'No Accepted Answer'
        WHEN qa.AcceptedAnswerCount > 0 THEN 'Has Accepted Answer'
        ELSE 'No Answers Yet'
    END AS AcceptanceStatus,
    CASE
        WHEN u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' AND u.Reputation > 5000 THEN 'Experienced High Rep User'
        WHEN u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years' THEN 'Long Time User'
        ELSE 'Newer User'
    END AS UserTenureCategory,
    UPPER(LEFT(COALESCE(u.Location, 'Unknown Location'), 3)) AS LocationAbbreviation,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(u.WebsiteUrl) > 0 THEN 'Has Website' ELSE 'No Website' END AS HasWebsite,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    CASE
        WHEN qa.AnswerCount > 50 THEN 'High Answer Volume'
        WHEN qa.AnswerCount > 10 THEN 'Moderate Answer Volume'
        ELSE 'Low Answer Volume'
    END AS AnswerVolumeCategory,
    q_tags.TagName AS PrimaryTag,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = qa.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinks
FROM QuestionAnswers qa
LEFT JOIN Users owner ON qa.QuestionOwnerUserId = owner.Id
LEFT JOIN PostEditCounts pec ON qa.QuestionId = pec.PostId
LEFT JOIN RankedPostEdits rpe ON qa.QuestionId = rpe.PostId AND rpe.rn = 1
LEFT JOIN Users u ON qa.QuestionOwnerUserId = u.Id
LEFT JOIN Tags q_tags ON SUBSTRING(qa.QuestionTitle FROM '#<([a-z0-9+.-]+)>#i') = q_tags.TagName -- Simplified tag extraction for demonstration
WHERE qa.AnswerCount > 0
UNION ALL
SELECT
    NULL AS QuestionId,
    NULL AS QuestionTitle,
    NULL AS QuestionOwner,
    NULL AS AnswerCount,
    NULL AS AcceptedAnswerCount,
    COUNT(ph.Id) AS PostTotalEdits,
    u.DisplayName AS EditorDisplayName,
    MAX(ph.CreationDate) AS LastEditDate,
    'N/A' AS AcceptanceStatus,
    CASE
        WHEN u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' AND u.Reputation > 5000 THEN 'Experienced High Rep User'
        WHEN u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years' THEN 'Long Time User'
        ELSE 'Newer User'
    END AS UserTenureCategory,
    UPPER(LEFT(COALESCE(u.Location, 'Unknown Location'), 3)) AS LocationAbbreviation,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(u.WebsiteUrl) > 0 THEN 'Has Website' ELSE 'No Website' END AS HasWebsite,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    'Overall System Activity' AS AnswerVolumeCategory,
    NULL AS PrimaryTag,
    NULL AS DuplicateLinks
FROM PostHistory ph
JOIN Users u ON ph.UserId = u.Id
WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
GROUP BY u.Id, u.DisplayName, UserTenureCategory, LocationAbbreviation, HasWebsite, GoldBadges, SilverBadges, BronzeBadges
HAVING COUNT(ph.Id) > 1000 -- Filter for users with significant edit activity
ORDER BY LastEditDate DESC NULLS LAST;