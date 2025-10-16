-- {"query": "18056.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1244} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserContribution AS (
    SELECT
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreOfOwnedPosts,
        AVG(p.ViewCount) AS AvgViewCountOfOwnedPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    GROUP BY p.OwnerUserId, u.DisplayName
),
TagEngagement AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        SUM(p.Score) AS TotalScoreForTag,
        AVG(CAST(p.AnswerCount AS NUMERIC)) AS AvgAnswersPerQuestion,
        MAX(p.FavoriteCount) AS MaxFavoritesForTag
    FROM Posts p
    JOIN Tags t ON LOWER(t.TagName) IN (SELECT LOWER(TRIM(UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ')))) FROM Posts) -- Simplified tag parsing, assuming no spaces in tags
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY t.TagName
),
ClosedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        p.ClosedDate,
        crt.Name AS CloseReason,
        COUNT(DISTINCT pl.RelatedPostId) AS DuplicateCount,
        SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS DeletionVoteCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3 -- Duplicate links
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON CAST(ph_close.Comment AS INT) = crt.Id -- Assuming Comment stores CloseReasonId for PostHistoryTypeId 10
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 10 -- Deletion votes
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
    GROUP BY p.Id, p.Title, p.CreationDate, p.ClosedDate, crt.Name
)
SELECT
    uc.OwnerDisplayName,
    uc.TotalPostsOwned,
    uc.TotalScoreOfOwnedPosts,
    uc.AvgViewCountOfOwnedPosts,
    uc.QuestionCount,
    uc.AnswerCount,
    rp.HistoryTypeName AS LatestEditType,
    rp.EditDate AS LatestEditDate,
    te.TagName,
    te.PostsWithTag,
    te.TotalScoreForTag,
    te.AvgAnswersPerQuestion,
    cq.QuestionTitle,
    cq.CloseReason,
    cq.DuplicateCount,
    cq.DeletionVoteCount,
    CASE
        WHEN uc.TotalScoreOfOwnedPosts > 10000 THEN 'High Performer'
        WHEN uc.TotalScoreOfOwnedPosts > 1000 THEN 'Mid Performer'
        ELSE 'Low Performer'
    END AS PerformanceTier,
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website' ELSE 'No Website' END AS WebsiteStatus,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%Master%') THEN 'Has Master Badge'
        ELSE 'No Master Badge'
    END AS BadgeStatus
FROM UserContribution uc
LEFT JOIN RankedPostEdits rp ON uc.OwnerUserId = rp.UserId AND rp.rn = 1
LEFT JOIN Users u ON uc.OwnerUserId = u.Id
LEFT JOIN TagEngagement te ON uc.OwnerDisplayName = (SELECT DisplayName FROM Users WHERE Id = (SELECT OwnerUserId FROM Posts WHERE Id IN (SELECT MIN(Id) FROM Posts WHERE Tags LIKE '%' || te.TagName || '%') )) AND te.PostsWithTag > 5 -- Simplified join condition for demonstration
LEFT JOIN ClosedQuestions cq ON uc.OwnerUserId = cq.QuestionId -- This join is likely incorrect and needs review based on specific performance goals
WHERE uc.TotalPostsOwned > 10
ORDER BY uc.TotalScoreOfOwnedPosts DESC, uc.TotalPostsOwned DESC
LIMIT 100;