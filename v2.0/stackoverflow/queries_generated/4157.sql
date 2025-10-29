-- {"query": "4157.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1377} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
),
UserEditActivity AS (
    SELECT
        rpe.UserId,
        COUNT(DISTINCT rpe.PostId) AS PostsEditedCount,
        AVG(p.AnswerCount) AS AvgAnswerCountForEditedPosts,
        MAX(p.Score) AS MaxScoreOfEditedPosts,
        SUM(CASE WHEN rpe.CreationDate < DATE('now', '-1 year') THEN 1 ELSE 0 END) AS OldEditsCount
    FROM RankedPostEdits rpe
    JOIN Posts p ON rpe.PostId = p.Id
    WHERE rpe.rn = 1 -- Only consider the latest edit by each user for a post
    GROUP BY rpe.UserId
),
UserPostInteraction AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostCreationDate,
        COUNT(DISTINCT CASE WHEN p.OwnerUserId = u.Id THEN p.Id ELSE NULL END) AS PostOwnedCount,
        COUNT(DISTINCT CASE WHEN p.LastEditorUserId = u.Id THEN p.Id ELSE NULL END) AS PostEditedByCount
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    GROUP BY u.Id, u.DisplayName
),
UserActivitySummary AS (
    SELECT
        upi.UserId,
        upi.DisplayName,
        upi.CommentCount,
        upi.UpVoteCount,
        upi.DownVoteCount,
        upi.BadgeCount,
        COALESCE(uea.PostsEditedCount, 0) AS TotalPostsEdited,
        COALESCE(uea.OldEditsCount, 0) AS OldEditsCount,
        COALESCE(uea.AvgAnswerCountForEditedPosts, 0) AS AvgAnswerCountForEditedPosts,
        COALESCE(uea.MaxScoreOfEditedPosts, 0) AS MaxScoreOfEditedPosts,
        upi.LastPostCreationDate,
        upi.PostOwnedCount,
        upi.PostEditedByCount
    FROM UserPostInteraction upi
    LEFT JOIN UserEditActivity uea ON upi.UserId = uea.UserId
)
SELECT
    uas.DisplayName,
    uas.CommentCount,
    uas.UpVoteCount,
    uas.DownVoteCount,
    uas.BadgeCount,
    uas.TotalPostsEdited,
    uas.OldEditsCount,
    CASE
        WHEN uas.TotalPostsEdited > 0 THEN CAST(uas.OldEditsCount AS REAL) / uas.TotalPostsEdited
        ELSE 0.0
    END AS PercentageOldEdits,
    uas.AvgAnswerCountForEditedPosts,
    uas.MaxScoreOfEditedPosts,
    uas.LastPostCreationDate,
    uas.PostOwnedCount,
    uas.PostEditedByCount,
    CASE
        WHEN uas.PostOwnedCount > 0 THEN CAST(uas.PostEditedByCount AS REAL) / uas.PostOwnedCount
        ELSE 0.0
    END AS EditRatio,
    (uas.UpVoteCount - uas.DownVoteCount) AS NetVoteScore,
    SUBSTRING(uas.DisplayName, 1, 3) AS DisplayNamePrefix,
    UPPER(COALESCE(uea.UserId::VARCHAR, 'N/A')) AS UserIDHashEquivalent -- Placeholder for potential hashing
FROM UserActivitySummary uas
LEFT JOIN UserEditActivity uea ON uas.UserId = uea.UserId
WHERE uas.BadgeCount > 5 OR uas.TotalPostsEdited > 10
UNION ALL
SELECT
    'Total' AS DisplayName,
    SUM(CommentCount) AS CommentCount,
    SUM(UpVoteCount) AS UpVoteCount,
    SUM(DownVoteCount) AS DownVoteCount,
    SUM(BadgeCount) AS BadgeCount,
    SUM(TotalPostsEdited) AS TotalPostsEdited,
    SUM(OldEditsCount) AS OldEditsCount,
    CASE
        WHEN SUM(TotalPostsEdited) > 0 THEN CAST(SUM(OldEditsCount) AS REAL) / SUM(TotalPostsEdited)
        ELSE 0.0
    END AS PercentageOldEdits,
    AVG(AvgAnswerCountForEditedPosts) AS AvgAnswerCountForEditedPosts,
    MAX(MaxScoreOfEditedPosts) AS MaxScoreOfEditedPosts,
    NULL AS LastPostCreationDate,
    SUM(PostOwnedCount) AS PostOwnedCount,
    SUM(PostEditedByCount) AS PostEditedByCount,
    CASE
        WHEN SUM(PostOwnedCount) > 0 THEN CAST(SUM(PostEditedByCount) AS REAL) / SUM(PostOwnedCount)
        ELSE 0.0
    END AS EditRatio,
    SUM(UpVoteCount - DownVoteCount) AS NetVoteScore,
    NULL AS DisplayNamePrefix,
    'TOTAL_HASH' AS UserIDHashEquivalent
FROM UserActivitySummary uas
LEFT JOIN UserEditActivity uea ON uas.UserId = uea.UserId
WHERE uas.BadgeCount > 5 OR uas.TotalPostsEdited > 10;