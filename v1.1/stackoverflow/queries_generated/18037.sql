-- {"query": "18037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1132} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostContributions AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
        SUM(p.FavoriteCount) AS TotalFavoritesReceived
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
PostEditCounts AS (
    SELECT
        rpe.UserId,
        COUNT(DISTINCT rpe.PostId) AS EditedPostsCount,
        MAX(rpe.CreationDate) AS LastEditDate
    FROM RankedPostEdits rpe
    GROUP BY rpe.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(upc.TotalPostsOwned, 0) AS PostsOwned,
    COALESCE(upc.QuestionsOwned, 0) AS QuestionsOwned,
    COALESCE(upc.AnswersOwned, 0) AS AnswersOwned,
    COALESCE(upc.TotalFavoritesReceived, 0) AS TotalFavoritesReceived,
    COALESCE(pec.EditedPostsCount, 0) AS EditedPostsCount,
    DATE(pec.LastEditDate) AS LastEditDate,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    ubs.BadgeNames,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.UserId = u.Id
          AND c.CreationDate >= DATE('now', '-1 year')
          AND LENGTH(c.Text) > 100
    ) AS LongCommentsLastYear,
    CASE
        WHEN u.Reputation > 100000 THEN 'High Reputation'
        WHEN u.Reputation > 10000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationCategory,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
        ELSE 'No Website'
    END AS WebsiteStatus,
    CASE
        WHEN u.LastAccessDate < DATE('now', '-365 days') THEN 'Inactive'
        ELSE 'Active'
    END AS UserActivityStatus,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostLinks pl
            JOIN Posts p ON pl.PostId = p.Id
            WHERE p.OwnerUserId = u.Id
              AND pl.LinkTypeId = 3 -- Duplicate Link
        ) THEN 'Has Duplicate Links'
        ELSE 'No Duplicate Links'
    END AS DuplicateLinkStatus,
    COALESCE(c_count.CommentCount, 0) AS TotalComments,
    CAST(STRFTIME('%Y', u.CreationDate) AS INTEGER) AS UserCreationYear,
    u.DisplayName || '_' || u.Id AS UniqueUserIdentifier
FROM Users u
LEFT JOIN UserPostContributions upc ON u.Id = upc.OwnerUserId
LEFT JOIN PostEditCounts pec ON u.Id = pec.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS CommentCount
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
) c_count ON u.Id = c_count.UserId
WHERE u.AccountId IS NOT NULL
  AND u.DownVotes > 0
  AND u.UpVotes > u.DownVotes * 5
  AND u.Views > 1000
  AND (u.Location LIKE '%USA%' OR u.Location LIKE '%Canada%')
ORDER BY u.Reputation DESC, u.CreationDate ASC
LIMIT 100;
