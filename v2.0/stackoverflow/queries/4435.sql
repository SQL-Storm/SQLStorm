WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5
),
HighReputationUsers AS (
    SELECT Id
    FROM Users
    WHERE Reputation > 10000
),
FrequentTagUsers AS (
    SELECT
        p.OwnerUserId,
        t.TagName,
        COUNT(p.Id) AS PostCount
    FROM Posts p
    JOIN Tags t ON POSITION(t.TagName IN p.Tags) > 0
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
    HAVING COUNT(p.Id) > 50
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(p.Score AS numeric)) AS AverageScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.Score > 5) AS HighlyScoredCommentCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.CreationDate,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.AverageScore,
    uas.LastPostActivityDate,
    uas.BadgeCount,
    uas.HighlyScoredCommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = uas.UserId AND v.VoteTypeId = 2) AS UpVotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = uas.UserId AND v.VoteTypeId = 3) AS DownVotesGiven,
    CASE
        WHEN uas.Reputation > 50000 THEN 'High Reputation'
        WHEN uas.Reputation > 10000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationLevel,
    CASE
        WHEN uas.LastPostActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year') THEN 'Active Last Year'
        WHEN uas.LastPostActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5 years') THEN 'Moderately Active'
        ELSE 'Inactive'
    END AS ActivityStatus,
    (
        SELECT ft.TagName
        FROM FrequentTagUsers ft
        WHERE ft.OwnerUserId = uas.UserId
        ORDER BY ft.PostCount DESC
        LIMIT 1
    ) AS TopFrequentTag,
    rpe.CreationDate AS LastEditDateForLatestPost,
    CASE
        WHEN uas.DisplayName ~ '[0-9]' THEN 'Contains Digits'
        ELSE 'No Digits'
    END AS DisplayNameNumericIndicator,
    COALESCE(u.WebsiteUrl, 'No Website') AS WebsiteInfo
FROM UserActivitySummary uas
LEFT JOIN Users u ON uas.UserId = u.Id
LEFT JOIN RankedPostEdits rpe ON uas.UserId = rpe.UserId AND rpe.rn = 1
WHERE uas.Reputation > 500
  AND (uas.QuestionCount + uas.AnswerCount) > 10
  AND uas.LastPostActivityDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')

UNION ALL

SELECT
    NULL AS UserId,
    'Community User' AS DisplayName,
    1 AS Reputation,
    MIN(p.CreationDate) AS CreationDate,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    AVG(CAST(p.Score AS numeric)) AS AverageScore,
    MAX(p.LastActivityDate) AS LastPostActivityDate,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT c.Id) AS HighlyScoredCommentCount,
    NULL AS UpVotesGiven,
    NULL AS DownVotesGiven,
    'Community' AS ReputationLevel,
    'Community' AS ActivityStatus,
    NULL AS TopFrequentTag,
    NULL AS LastEditDateForLatestPost,
    'N/A' AS DisplayNameNumericIndicator,
    'N/A' AS WebsiteInfo
FROM Posts p
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN Comments c ON p.OwnerUserId = c.UserId AND c.Score > 5
WHERE p.OwnerUserId = -1
GROUP BY
    -- group by all non-aggregated selected expressions; NULL is replaced by constants already selected
    -- the only non-aggregated expressions are the constant DisplayName, Reputation, ActivityStatus, etc.
    -- SQL requires grouping by those constant expressions as literals; using explicit constants is fine:
    -- Since UserId, DisplayName, Reputation, ActivityStatus, ReputationLevel, TopFrequentTag, LastEditDateForLatestPost,
    -- DisplayNameNumericIndicator, WebsiteInfo are constants or NULLs in this SELECT, we can GROUP BY the constants to satisfy SQL.
    -- Use the same literal expressions as in the SELECT:
    'Community User',
    1,
    'Community',
    'Community',
    'N/A',
    'N/A'

ORDER BY Reputation DESC, LastPostActivityDate DESC;