-- {"query": "4785.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1770}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostContributions AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS TotalDownVotesGiven,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (
            SELECT MAX(ph.CreationDate)
            FROM PostHistory ph
            WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
        ) AS LastEditDate
    FROM Users u
    LEFT JOIN UserPostContributions upc ON u.Id = upc.OwnerUserId
    WHERE u.Id IS NOT NULL AND u.Id > 0
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    u_owner.DisplayName AS OwnerDisplayName,
    u_editor.DisplayName AS LastEditorDisplayName,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS ActualCommentCount,
    ua.Reputation AS OwnerReputation,
    ua.TotalQuestions AS OwnerTotalQuestions,
    ua.TotalAnswers AS OwnerTotalAnswers,
    ua.TotalUpVotesGiven AS OwnerTotalUpVotesGiven,
    ua.GoldBadges AS OwnerGoldBadges,
    ua.SilverBadges AS OwnerSilverBadges,
    ua.BronzeBadges AS OwnerBronzeBadges,
    CASE
        WHEN p.OwnerUserId = rpe.UserId AND rpe.rn = 1 THEN 'FirstEditor'
        WHEN p.OwnerUserId <> p.LastEditorUserId THEN 'DifferentEditor'
        ELSE 'SameEditorOrNew'
    END AS EditorStatus,
    COALESCE(p.Tags, 'NoTags') AS FormattedTags,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN CAST(p.ClosedDate AS DATE) - CAST(p.CreationDate AS DATE)
        ELSE NULL
    END AS TimeToCloseDays,
    LOWER(REPLACE(REPLACE(p.Body, '<p>', ''), '</p>', '')) AS CleanedPostBody,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
LEFT JOIN Users u_editor ON p.LastEditorUserId = u_editor.Id
LEFT JOIN UserActivitySummary ua ON p.OwnerUserId = ua.UserId
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE p.PostTypeId IN (1, 2)
  AND p.Score > 0
  AND p.ViewCount > 100
  AND (p.Title LIKE '%SQL%' OR p.Body LIKE '%SQL%')
  AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.UserId IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3)

UNION

SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    u_owner.DisplayName AS OwnerDisplayName,
    u_editor.DisplayName AS LastEditorDisplayName,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS ActualCommentCount,
    ua.Reputation AS OwnerReputation,
    ua.TotalQuestions AS OwnerTotalQuestions,
    ua.TotalAnswers AS OwnerTotalAnswers,
    ua.TotalUpVotesGiven AS OwnerTotalUpVotesGiven,
    ua.GoldBadges AS OwnerGoldBadges,
    ua.SilverBadges AS OwnerSilverBadges,
    ua.BronzeBadges AS OwnerBronzeBadges,
    CASE
        WHEN p.OwnerUserId = rpe.UserId AND rpe.rn = 1 THEN 'FirstEditor'
        WHEN p.OwnerUserId <> p.LastEditorUserId THEN 'DifferentEditor'
        ELSE 'SameEditorOrNew'
    END AS EditorStatus,
    COALESCE(p.Tags, 'NoTags') AS FormattedTags,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN CAST(p.ClosedDate AS DATE) - CAST(p.CreationDate AS DATE)
        ELSE NULL
    END AS TimeToCloseDays,
    LOWER(REPLACE(REPLACE(p.Body, '<p>', ''), '</p>', '')) AS CleanedPostBody,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u_owner ON p.OwnerUserId = u_owner.Id
LEFT JOIN Users u_editor ON p.LastEditorUserId = u_editor.Id
LEFT JOIN UserActivitySummary ua ON p.OwnerUserId = ua.UserId
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE p.PostTypeId = 1
  AND p.Score < 0
  AND p.AnswerCount > 5
  AND (p.Title LIKE '%performance%' OR p.Body LIKE '%performance%')
  AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10)
ORDER BY LastActivityDate DESC
LIMIT 100;