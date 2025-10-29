-- {"query": "4011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 842} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 7, 8, 9)
),
UserPostContribution AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(CAST(p.ViewCount AS DECIMAL(10, 2))) AS AvgViewCount
    FROM Posts p
    WHERE p.PostTypeId = 2 /* Answers */
    GROUP BY p.OwnerUserId
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.Reputation, 0) AS UserReputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
)
SELECT
    u.DisplayName,
    COALESCE(upc.PostCount, 0) AS AnswerCount,
    COALESCE(upc.TotalScore, 0) AS TotalAnswerScore,
    COALESCE(upc.AvgViewCount, 0.00) AS AverageAnswerViewCount,
    upa.UserReputation,
    upa.UserCreationDate,
    upa.CommentCount,
    CASE
        WHEN upa.LastCommentDate IS NULL THEN 'Never'
        ELSE CAST(strftime('%Y-%m-%d %H:%M:%S', upa.LastCommentDate) AS TEXT)
    END AS LastCommentTimestamp,
    (
        SELECT
            COUNT(DISTINCT rpe1.PostId)
        FROM RankedPostEdits rpe1
        WHERE rpe1.UserId = u.Id
    ) AS TotalEditsMade,
    (
        SELECT
            COUNT(DISTINCT rpe2.PostId)
        FROM RankedPostEdits rpe2
        WHERE rpe2.UserId = u.Id AND rpe2.rn = 1
    ) AS PostsWithMostRecentEdit,
    (
        SELECT
            COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0)
        FROM PostHistory ph
        WHERE ph.UserId = u.Id
    ) AS TotalPostsClosed,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Name LIKE '%Master%' AND b.Class = 1 /* Gold badge */
        ) THEN 'Has Gold Master Badge'
        ELSE 'No Gold Master Badge'
    END AS BadgeStatus
FROM Users u
LEFT JOIN UserPostContribution upc ON u.Id = upc.OwnerUserId
LEFT JOIN UserPostActivity upa ON u.Id = upa.UserId
WHERE u.DisplayName IS NOT NULL
  AND u.Reputation > 1000
  AND u.Views > 5000
  AND (u.Location LIKE '%USA%' OR u.Location LIKE '%Canada%')
  AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 /* Question */ AND p.AnswerCount > 5)
ORDER BY UserReputation DESC, TotalAnswerScore DESC
LIMIT 50;