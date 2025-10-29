-- {"query": "4332.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1021} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
LatestPostEdits AS (
    SELECT
        rpe.PostId,
        rpe.UserId AS LastEditorUserId,
        rpe.CreationDate AS LastEditDate,
        p.OwnerUserId
    FROM RankedPostEdits rpe
    JOIN Posts p ON rpe.PostId = p.Id
    WHERE rpe.rn = 1
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        SUM(p.ViewCount) AS TotalViewCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(ups.QuestionCount, 0) AS TotalQuestions,
        COALESCE(ups.AnswerCount, 0) AS TotalAnswers,
        COALESCE(ups.AverageScore, 0) AS AvgPostScore,
        COALESCE(ups.TotalViewCount, 0) AS TotalPostViews,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    WHERE u.Id IS NOT NULL AND u.Id > 0
)
SELECT
    p.Id AS PostId,
    p.Title,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COALESCE(lpe.LastEditDate, p.CreationDate) AS LastActivityOnPost,
    COALESCE(lpe.LastEditorUserId, p.OwnerUserId) AS LastEditorUserId,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.AvgPostScore,
    ua.TotalPostViews,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    CONCAT(
        'Owner: ', u.DisplayName, ' (Rep: ', u.Reputation, ') | '
    ) ||
    CASE
        WHEN lpe.LastEditorUserId IS NOT NULL THEN
            (SELECT DisplayName FROM Users WHERE Id = lpe.LastEditorUserId)
        ELSE
            'N/A'
    END ||
    CASE
        WHEN lpe.LastEditorUserId IS NOT NULL THEN
            ' (Last Editor)'
        ELSE
            ''
    END AS PostMetaData
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN LatestPostEdits lpe ON p.Id = lpe.PostId
LEFT JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
WHERE p.Score > 10
  AND ua.UserCreationDate < '2015-01-01'
  AND ua.AvgPostScore > 15
  AND p.AnswerCount BETWEEN 1 AND 10
  AND ua.TotalPostViews > 10000
ORDER BY p.LastActivityDate DESC
LIMIT 50;
