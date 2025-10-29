-- {"query": "4433.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 885} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        p.OwnerUserId AS OriginalOwnerUserId,
        p.Title AS OriginalTitle,
        p.Tags AS OriginalTags,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 6) -- Edit Title, Edit Tags
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AverageViewCount,
        MAX(p.CreationDate) AS LatestPostCreation
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY p.OwnerUserId
),
PostEditFrequency AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS NumberOfUniqueEditors,
        COUNT(*) AS TotalEditEvents
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId
),
TopUsersWithBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Users u
    JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class = 1 -- Gold badges
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(b.Id) > 5
)
SELECT
    COALESCE(t.UserId, c.UserId) AS UserIdentifier,
    COALESCE(t.DisplayName, c.DisplayName, 'Deleted User') AS DisplayName,
    COALESCE(upa.TotalPostsOwned, 0) AS PostsOwned,
    COALESCE(upa.TotalScore, 0) AS TotalScoreReceived,
    COALESCE(upa.AverageViewCount, 0.0) AS AvgPostViews,
    COALESCE(pef.NumberOfUniqueEditors, 0) AS DistinctEditorsOnPosts,
    COALESCE(pef.TotalEditEvents, 0) AS TotalPostEdits,
    COALESCE(t.BadgeCount, 0) AS GoldBadgeCount,
    t.BadgeNames,
    (
        SELECT COUNT(*)
        FROM Comments c_inner
        WHERE c_inner.UserId = COALESCE(t.UserId, c.UserId)
        AND c_inner.Score > 10
    ) AS HighScoringCommentCount,
    CASE
        WHEN upa.LatestPostCreation > DATE('now', '-1 year') THEN 'Active'
        WHEN upa.LatestPostCreation <= DATE('now', '-1 year') AND upa.LatestPostCreation IS NOT NULL THEN 'Inactive'
        ELSE 'No Posts'
    END AS UserActivityStatus
FROM TopUsersWithBadges t
FULL OUTER JOIN UserPostActivity upa ON t.UserId = upa.OwnerUserId
FULL OUTER JOIN PostEditFrequency pef ON COALESCE(t.UserId, upa.OwnerUserId) = (SELECT OwnerUserId FROM Posts p_sub WHERE p_sub.Id = pef.PostId)
LEFT JOIN Users c ON COALESCE(t.UserId, upa.OwnerUserId) = c.Id
WHERE COALESCE(t.BadgeCount, 0) > 0 OR COALESCE(upa.TotalPostsOwned, 0) > 100
ORDER BY TotalScoreReceived DESC, GoldBadgeCount DESC
LIMIT 50;