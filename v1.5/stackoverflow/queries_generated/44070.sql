-- {"query": "44070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 797}

SELECT 
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Id AS UserId,
    u.Reputation,
    u.DisplayName,
    u.Location,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.TagBased AS BadgeTagBased,
    CONCAT(ROUND(DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) / 365.25, 2), ' years') AS PostAge,
    CONCAT(ROUND(DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) / 365.25, 2), ' years') AS UserAge,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN v.VoteTypeId = 2 THEN 'Upvote'
        WHEN v.VoteTypeId = 3 THEN 'Downvote'
        WHEN v.VoteTypeId = 5 THEN 'Favorite'
        WHEN v.VoteTypeId = 6 THEN 'Close'
        WHEN v.VoteTypeId = 7 THEN 'Reopen'
        WHEN v.VoteTypeId = 10 THEN 'Deletion'
        WHEN v.VoteTypeId = 11 THEN 'Undeletion'
        WHEN v.VoteTypeId = 12 THEN 'Spam'
        WHEN v.VoteTypeId = 14 THEN 'Nominate Moderator'
        WHEN v.VoteTypeId = 15 THEN 'Moderator Review'
        WHEN v.VoteTypeId = 16 THEN 'Approve Edit Suggestion'
        ELSE 'Other'
    END AS VoteType,
    COALESCE(v.BountyAmount, 0) AS BountyAmount,
    COALESCE(ph.Comment, '') AS PostHistoryComment,
    COALESCE(ph.Text, '') AS PostHistoryText,
    CASE 
        WHEN ph.PostHistoryTypeId = 10 THEN (SELECT Name FROM CloseReasonTypes WHERE Id = CAST(ph.Comment AS SMALLINT))
        WHEN ph.PostHistoryTypeId IN (33, 34) THEN (SELECT Name FROM PostNotices WHERE Id = CAST(ph.Comment AS INT))
        ELSE ''
    END AS PostHistoryDetails
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
ORDER BY p.Id, v.CreationDate;
