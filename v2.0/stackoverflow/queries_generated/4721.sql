-- {"query": "4721.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1243} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) as PreviousEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(u.LastAccessDate) AS LastSeen
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        COUNT(DISTINCT c.Id) AS CommentCountPerPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.Title, p.Score, p.CommentCount, p.FavoriteCount, p.AnswerCount, p.ClosedDate
)
SELECT
    uas.DisplayName AS UserDisplayName,
    uas.Reputation,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalBadges,
    uas.LastSeen,
    pe.Title AS LatestQuestionTitle,
    pe.Score AS LatestQuestionScore,
    pe.CommentCountPerPost,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.PostStatus,
    rpe.CreationDate AS LatestEditDate,
    rpe.rn AS EditSequenceNumber,
    -- Calculating time between edits for the same user on the same post
    CASE
        WHEN rpe.rn > 1 THEN
            DATE_PART('epoch', rpe.CreationDate - rpe.PreviousEditDate)
        ELSE
            NULL
    END AS TimeSincePreviousEditSeconds,
    -- Example of a complex string expression and NULL logic
    CASE
        WHEN uas.DisplayName IS NULL THEN 'Anonymous'
        WHEN uas.Reputation > 10000 THEN UPPER(SUBSTRING(uas.DisplayName, 1, 3)) || '...' || LOWER(SUBSTRING(uas.DisplayName FROM LENGTH(uas.DisplayName) - 2))
        WHEN uas.Reputation BETWEEN 1000 AND 10000 THEN 'User-' || uas.Id
        ELSE 'New User'
    END AS UserIdentifier,
    -- Using a window function to rank posts by score for each user
    RANK() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRankByScore
FROM Users uas
JOIN PostEngagement pe ON uas.Id = pe.UserId
LEFT JOIN RankedPostEdits rpe ON uas.Id = rpe.UserId AND pe.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN Posts p ON uas.Id = p.OwnerUserId -- Joining to Posts again to use in window function
WHERE uas.CreationDate < '2023-01-01' -- Filtering for older users
  AND uas.Location IS NOT NULL
  AND pe.Score > 0
  AND EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = uas.Id AND v.VoteTypeId = 2) -- Users who have at least one upvote
UNION
SELECT
    NULL AS UserDisplayName,
    NULL AS Reputation,
    NULL AS TotalQuestions,
    NULL AS TotalAnswers,
    NULL AS TotalBadges,
    NULL AS LastSeen,
    'Community Owned Question' AS LatestQuestionTitle,
    NULL AS LatestQuestionScore,
    NULL AS CommentCountPerPost,
    NULL AS UpVoteCount,
    NULL AS DownVoteCount,
    'Open' AS PostStatus,
    NULL AS LatestEditDate,
    NULL AS EditSequenceNumber,
    NULL AS TimeSincePreviousEditSeconds,
    'Community' AS UserIdentifier,
    NULL AS PostRankByScore
FROM Posts p
WHERE p.OwnerUserId = -1 -- Community user
  AND p.PostTypeId = 1 -- Questions
  AND p.CreationDate > '2022-01-01'
ORDER BY UserDisplayName, LatestEditDate DESC;
