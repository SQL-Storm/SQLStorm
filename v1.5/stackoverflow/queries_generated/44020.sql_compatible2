SELECT
    u.DisplayName AS UserName,
    u.Reputation AS UserReputation,
    p.Title AS PostTitle,
    p.Body AS PostBody,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount AS PostAnswerCount,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount AS PostFavoriteCount,
    CASE p.PostTypeId
        WHEN 1 THEN 'Question'
        WHEN 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostType,
    CAST(p.CreationDate AS DATE) AS PostCreationDate,
    CAST(p.LastActivityDate AS DATE) AS PostLastActivityDate,
    CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) AS BIGINT) AS PostDuration,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS PostStatus,
    COALESCE(ph.Text, '') AS PostHistoryText,
    COALESCE(ph.Comment, '') AS PostHistoryComment,
    CAST(ph.CreationDate AS DATE) AS PostHistoryCreationDate,
    u2.DisplayName AS PostHistoryUserName,
    CASE ph.PostHistoryTypeId
        WHEN 1 THEN 'Initial Title'
        WHEN 2 THEN 'Initial Body'
        WHEN 3 THEN 'Initial Tags'
        WHEN 4 THEN 'Edit Title'
        WHEN 5 THEN 'Edit Body'
        WHEN 6 THEN 'Edit Tags'
        WHEN 7 THEN 'Rollback Title'
        WHEN 8 THEN 'Rollback Body'
        WHEN 9 THEN 'Rollback Tags'
        WHEN 10 THEN 'Post Closed'
        WHEN 11 THEN 'Post Reopened'
        WHEN 12 THEN 'Post Deleted'
        WHEN 13 THEN 'Post Undeleted'
        WHEN 14 THEN 'Post Locked'
        WHEN 15 THEN 'Post Unlocked'
        WHEN 16 THEN 'Community Owned'
        WHEN 17 THEN 'Post Migrated'
        WHEN 18 THEN 'Question Merged'
        WHEN 19 THEN 'Question Protected'
        WHEN 20 THEN 'Question Unprotected'
        WHEN 22 THEN 'Suggested Edit Applied'
        WHEN 25 THEN 'Post Tweeted'
        WHEN 31 THEN 'Discussion Moved to Chat'
        WHEN 33 THEN 'Post Notice Added'
        WHEN 34 THEN 'Post Notice Removed'
        WHEN 35 THEN 'Post Migrated Away'
        WHEN 36 THEN 'Post Migrated Here'
        WHEN 37 THEN 'Post Merge Source'
        WHEN 38 THEN 'Post Merge Destination'
        WHEN 50 THEN 'Community Bumped'
        WHEN 52 THEN 'Selected Hot Question'
        WHEN 53 THEN 'Removed Hot Question'
        WHEN 66 THEN 'Created From Wizard'
        ELSE 'Unknown'
    END AS PostHistoryType,
    CASE
        WHEN ph.PostHistoryTypeId = 10 THEN
            CASE crt.Id
                WHEN 1 THEN 'Exact Duplicate'
                WHEN 2 THEN 'Off-topic'
                WHEN 3 THEN 'Subjective and Argumentative'
                WHEN 4 THEN 'Not a Real Question'
                WHEN 7 THEN 'Too Localized'
                WHEN 10 THEN 'General Reference'
                WHEN 101 THEN 'Duplicate'
                WHEN 102 THEN 'Off-topic'
                WHEN 103 THEN 'Needs Details or Clarity'
                WHEN 104 THEN 'Needs More Focus'
                WHEN 105 THEN 'Opinion-based'
                ELSE 'Unknown'
            END
        ELSE ''
    END AS CloseReason,
    CASE
        WHEN ph.PostHistoryTypeId IN (33, 34) THEN
            CAST(ph.Text AS INTEGER)
        ELSE NULL
    END AS PostNoticeId
FROM Posts p
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Users u2 ON ph.UserId = u2.Id
LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS VARCHAR) = CAST(crt.Id AS VARCHAR)
ORDER BY p.Id, ph.CreationDate;