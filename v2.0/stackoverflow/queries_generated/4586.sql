-- {"query": "4586.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2328} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.UserDisplayName,
        ph.CreationDate AS EditDate,
        p.Title,
        p.Tags,
        p.OwnerUserId AS OriginalOwnerUserId,
        p.LastEditorUserId AS CurrentLastEditorUserId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserEditSummary AS (
    SELECT
        UserId,
        DisplayName,
        CreationDate AS UserCreationDate,
        LastAccessDate AS UserLastAccessDate,
        Reputation AS UserReputation,
        Views AS UserViews,
        UpVotes AS UserUpVotes,
        DownVotes AS UserDownVotes,
        COUNT(DISTINCT rpe.PostId) AS DistinctPostsEdited,
        SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
        SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
        SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
        AVG(JULIANDAY(rpe.EditDate) - JULIANDAY(u.CreationDate)) AS AvgDaysSinceUserCreation,
        MAX(rpe.EditDate) AS LatestEditDate
    FROM Users u
    LEFT JOIN RankedPostEdits rpe ON u.Id = rpe.UserId
    GROUP BY
        UserId, DisplayName, UserCreationDate, UserLastAccessDate, UserReputation, UserViews, UserUpVotes, UserDownVotes
),
PostEditDetails AS (
    SELECT
        rpe.PostId,
        rpe.PostHistoryTypeId,
        rpe.UserId AS EditorUserId,
        ues.DisplayName AS EditorDisplayName,
        rpe.EditDate,
        rpe.Title AS EditedTitle,
        rpe.Tags AS EditedTags,
        ues.UserReputation AS EditorReputation,
        CASE
            WHEN ues.UserReputation > 100000 THEN 'High Reputation'
            WHEN ues.UserReputation BETWEEN 10000 AND 100000 THEN 'Medium Reputation'
            ELSE 'Low Reputation'
        END AS EditorReputationTier,
        rpe.rn
    FROM RankedPostEdits rpe
    JOIN UserEditSummary ues ON rpe.UserId = ues.UserId
    WHERE rpe.rn = 1
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    p.Tags,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    COALESCE(orig_user.DisplayName, p.OwnerDisplayName) AS OriginalOwnerDisplayName,
    orig_user.Reputation AS OriginalOwnerReputation,
    COALESCE(last_editor.DisplayName, p.LastEditorDisplayName) AS LastEditorDisplayName,
    last_editor.Reputation AS LastEditorReputation,
    ped.EditDate,
    ped.EditedTitle,
    ped.EditedTags,
    ped.EditorReputationTier,
    CASE
        WHEN p.ClosedDate IS NOT NULL AND p.ClosedDate > DATETIME('now', '-30 day') THEN 'Recently Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForThisPost,
    SUM(v.VoteTypeId = 2) OVER (PARTITION BY p.Id) AS UpVoteCount,
    SUM(v.VoteTypeId = 3) OVER (PARTITION BY p.Id) AS DownVoteCount,
    CASE
        WHEN SUBSTR(p.ContentLicense, 1, 3) = 'CC-' THEN 'Creative Commons'
        ELSE p.ContentLicense
    END AS FormattedContentLicense,
    IIF(p.Title LIKE '%?%', 'Ends with Question Mark', 'Does Not End with Question Mark') AS TitleEndsWithQuestionMark,
    COALESCE(pl.LinkTypeId, 0) AS PostLinkType,
    (SELECT COUNT(*) FROM PostHistory ph_inner WHERE ph_inner.PostId = p.Id AND ph_inner.PostHistoryTypeId IN (10, 11)) AS CloseReopenHistoryCount,
    CASE WHEN p.ParentId IS NOT NULL THEN 'Is Answer' ELSE 'Is Question/Other' END AS IsAnswerFlag
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users orig_user ON p.OwnerUserId = orig_user.Id
LEFT JOIN Users last_editor ON p.LastEditorUserId = last_editor.Id
LEFT JOIN PostEditDetails ped ON p.Id = ped.PostId AND ped.rn = 1
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
WHERE p.CreationDate >= DATE('now', '-1 year')
  AND p.Score > 5
  AND p.AnswerCount >= 0 -- Placeholder for potential future filtering
GROUP BY
    p.Id, pt.Name, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
    OriginalOwnerDisplayName, OriginalOwnerReputation, LastEditorDisplayName, LastEditorReputation,
    ped.EditDate, ped.EditedTitle, ped.EditedTags, ped.EditorReputationTier,
    PostStatus, FormattedContentLicense, TitleEndsWithQuestionMark, PostLinkType, CloseReopenHistoryCount, IsAnswerFlag
HAVING COUNT(DISTINCT v.Id) > 10 -- Only consider posts with significant voting activity
UNION
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    p.Tags,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    COALESCE(orig_user.DisplayName, p.OwnerDisplayName) AS OriginalOwnerDisplayName,
    orig_user.Reputation AS OriginalOwnerReputation,
    COALESCE(last_editor.DisplayName, p.LastEditorDisplayName) AS LastEditorDisplayName,
    last_editor.Reputation AS LastEditorReputation,
    ped.EditDate,
    ped.EditedTitle,
    ped.EditedTags,
    ped.EditorReputationTier,
    CASE
        WHEN p.ClosedDate IS NOT NULL AND p.ClosedDate > DATETIME('now', '-30 day') THEN 'Recently Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForThisPost,
    SUM(v.VoteTypeId = 2) OVER (PARTITION BY p.Id) AS UpVoteCount,
    SUM(v.VoteTypeId = 3) OVER (PARTITION BY p.Id) AS DownVoteCount,
    CASE
        WHEN SUBSTR(p.ContentLicense, 1, 3) = 'CC-' THEN 'Creative Commons'
        ELSE p.ContentLicense
    END AS FormattedContentLicense,
    IIF(p.Title LIKE '%?%', 'Ends with Question Mark', 'Does Not End with Question Mark') AS TitleEndsWithQuestionMark,
    COALESCE(pl.LinkTypeId, 0) AS PostLinkType,
    (SELECT COUNT(*) FROM PostHistory ph_inner WHERE ph_inner.PostId = p.Id AND ph_inner.PostHistoryTypeId IN (10, 11)) AS CloseReopenHistoryCount,
    CASE WHEN p.ParentId IS NOT NULL THEN 'Is Answer' ELSE 'Is Question/Other' END AS IsAnswerFlag
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users orig_user ON p.OwnerUserId = orig_user.Id
LEFT JOIN Users last_editor ON p.LastEditorUserId = last_editor.Id
LEFT JOIN PostEditDetails ped ON p.Id = ped.PostId AND ped.rn = 1
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
WHERE p.CreationDate >= DATE('now', '-1 year')
  AND p.Score <= 5
  AND p.AnswerCount BETWEEN 0 AND 5 -- Placeholder for potential future filtering
GROUP BY
    p.Id, pt.Name, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate,
    OriginalOwnerDisplayName, OriginalOwnerReputation, LastEditorDisplayName, LastEditorReputation,
    ped.EditDate, ped.EditedTitle, ped.EditedTags, ped.EditorReputationTier,
    PostStatus, FormattedContentLicense, TitleEndsWithQuestionMark, PostLinkType, CloseReopenHistoryCount, IsAnswerFlag
HAVING COUNT(DISTINCT v.Id) <= 10 -- Posts with less significant voting activity
