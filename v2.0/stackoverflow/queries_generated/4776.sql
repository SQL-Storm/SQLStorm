-- {"query": "4776.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1496} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn,
        SUM(CASE WHEN pht.Name = 'Edit Body' THEN 1 ELSE 0 END) OVER(PARTITION BY ph.PostId, ph.UserId) as total_body_edits,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) as previous_edit_date
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (5, 4, 6) -- Edit Body, Edit Title, Edit Tags
    AND ph.UserId IS NOT NULL
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS NumberOfQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumberOfAnswers,
        COUNT(DISTINCT b.Id) AS NumberOfBadges,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(COALESCE(p.Score, 0)) AS AveragePostScore,
        SUM(CASE WHEN p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS PostsOwned,
        COUNT(DISTINCT ph.Id) AS TotalEdits
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.Id BETWEEN 10000 AND 50000 -- Focusing on a subset of users
    GROUP BY u.Id, u.DisplayName
),
PostEditFrequency AS (
    SELECT
        rpe.PostId,
        rpe.UserId,
        rpe.total_body_edits,
        (rpe.CreationDate - rpe.previous_edit_date) AS time_between_edits_ms,
        CASE
            WHEN (rpe.CreationDate - rpe.previous_edit_date) < INTERVAL '1 hour' THEN 'Frequent'
            WHEN (rpe.CreationDate - rpe.previous_edit_date) BETWEEN INTERVAL '1 hour' AND INTERVAL '1 day' THEN 'Regular'
            ELSE 'Infrequent'
        END AS edit_frequency
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
),
AggregatedPostData AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.LastEditDate,
        u.DisplayName AS OwnerDisplayName,
        SUM(CASE WHEN c.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnCommentsCount,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.CreationDate > '2023-01-01'
    GROUP BY p.Id, pt.Name, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.OwnerUserId, p.LastEditDate, u.DisplayName, p.ClosedDate, p.CommunityOwnedDate
)
SELECT
    apd.PostId,
    apd.PostType,
    apd.Title,
    apd.OwnerDisplayName,
    apd.CreationDate,
    apd.Score,
    apd.ViewCount,
    apd.AnswerCount,
    apd.CommentCount,
    apd.FavoriteCount,
    apd.PostStatus,
    uc.NumberOfQuestions,
    uc.NumberOfAnswers,
    uc.NumberOfBadges,
    uc.TotalEdits AS UserTotalEdits,
    pef.edit_frequency,
    CASE
        WHEN apd.PostStatus = 'Closed' AND apd.Score < 0 THEN 'Potentially Abusive Closure'
        WHEN apd.PostStatus = 'Active' AND apd.CommentCount > 50 AND apd.Score > 10 THEN 'Highly Discussed and Valued'
        WHEN apd.PostStatus = 'Community Owned' AND apd.LastEditDate IS NULL THEN 'Orphaned Community Content'
        WHEN apd.Score > 100 AND apd.AnswerCount > 5 THEN 'High Impact Question'
        WHEN apd.PostType = 'Answer' AND apd.Score < 0 AND apd.OwnCommentsCount > 0 THEN 'Contentious Answer'
        WHEN apd.PostType = 'Question' AND apd.AnswerCount = 0 AND apd.FavoriteCount > 10 AND apd.Score > 5 THEN 'Highly Favorited Unanswered Question'
        ELSE 'Standard'
    END AS PerformanceCategory,
    CONCAT(COALESCE(u.Location, 'Unknown Location'), ' - ', COALESCE(u.WebsiteUrl, 'No Website')) AS UserLocationAndSite,
    COALESCE(apd.Score, 0) + COALESCE(apd.ViewCount, 0) / 1000 AS CompositeScore
FROM AggregatedPostData apd
LEFT JOIN UserContribution uc ON apd.OwnerUserId = uc.UserId
LEFT JOIN PostEditFrequency pef ON apd.PostId = pef.PostId AND apd.OwnerUserId = pef.UserId
LEFT JOIN Users u ON apd.OwnerUserId = u.Id
WHERE apd.Score > 0 OR apd.CommentCount > 0
ORDER BY apd.CreationDate DESC
LIMIT 1000;
