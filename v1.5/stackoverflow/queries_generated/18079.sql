-- {"query": "18079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1385} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditCounts AS (
    SELECT
        PostId,
        COUNT(DISTINCT UserId) AS DistinctEditors,
        SUM(CASE WHEN rn = 1 THEN 1 ELSE 0 END) AS FirstEditsMade
    FROM RankedPostEdits
    GROUP BY PostId
    HAVING COUNT(DISTINCT UserId) > 2
),
FrequentUsers AS (
    SELECT
        UserId,
        COUNT(*) AS PostCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
    GROUP BY UserId
    HAVING COUNT(*) > 1000
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Posts p
    JOIN FrequentUsers fu ON p.OwnerUserId = fu.UserId
    WHERE p.CreationDate >= DATE('now', '-1 year')
    GROUP BY p.OwnerUserId
),
UserReputationChange AS (
    SELECT
        u.Id AS UserId,
        u.Reputation - LAG(u.Reputation, 1, u.Reputation) OVER (ORDER BY u.CreationDate) AS ReputationDelta,
        u.DisplayName
    FROM Users u
    WHERE u.CreationDate >= DATE('now', '-1 year')
),
HighActivityUsers AS (
    SELECT
        upa.OwnerUserId,
        upa.TotalPosts,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AverageScore,
        urc.ReputationDelta,
        urc.DisplayName AS UserDisplayName
    FROM UserPostActivity upa
    JOIN UserReputationChange urc ON upa.OwnerUserId = urc.UserId
    WHERE upa.AverageScore > 50 AND upa.AnswerCount > upa.QuestionCount * 2
)
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    p.Score AS PostScore,
    p.AnswerCount,
    p.CommentCount,
    CASE
        WHEN p.FavoriteCount > 0 THEN 'Favorited'
        WHEN p.ViewCount > 10000 THEN 'Highly Viewed'
        ELSE 'Standard'
    END AS PostStatus,
    ha.UserDisplayName AS HighActivityUserName,
    ha.TotalPosts AS HighActivityUserTotalPosts,
    ha.ReputationDelta AS HighActivityUserReputationDelta,
    ph_edit.EditorDisplayName AS LastEditorDisplayName,
    ph_edit.CreationDate AS LastEditDate,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id AND c.Score > 5
    ) AS HighScoringCommentCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostClosureStatus,
    COALESCE(p.OwnerDisplayName, 'Community') AS ActualOwnerDisplayName,
    p.Tags AS OriginalTags
FROM Posts p
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostEditCounts pec ON p.Id = pec.PostId
LEFT JOIN HighActivityUsers ha ON p.OwnerUserId = ha.OwnerUserId
LEFT JOIN RankedPostEdits ph_edit ON p.Id = ph_edit.PostId AND ph_edit.rn = 1
WHERE p.Score > 10
UNION
SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    p.Score AS PostScore,
    p.AnswerCount,
    p.CommentCount,
    CASE
        WHEN p.FavoriteCount > 0 THEN 'Favorited'
        WHEN p.ViewCount > 10000 THEN 'Highly Viewed'
        ELSE 'Standard'
    END AS PostStatus,
    NULL AS HighActivityUserName,
    NULL AS HighActivityUserTotalPosts,
    NULL AS HighActivityUserReputationDelta,
    NULL AS LastEditorDisplayName,
    NULL AS LastEditDate,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.PostId = p.Id AND c.Score > 5
    ) AS HighScoringCommentCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostClosureStatus,
    COALESCE(p.OwnerDisplayName, 'Community') AS ActualOwnerDisplayName,
    p.Tags AS OriginalTags
FROM Posts p
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostEditCounts pec ON p.Id = pec.PostId
LEFT JOIN HighActivityUsers ha ON p.OwnerUserId = ha.OwnerUserId
LEFT JOIN RankedPostEdits ph_edit ON p.Id = ph_edit.PostId AND ph_edit.rn = 1
WHERE p.Score <= 10 AND pec.DistinctEditors IS NULL AND ha.OwnerUserId IS NULL
ORDER BY PostScore DESC, PostCreationDate DESC;
