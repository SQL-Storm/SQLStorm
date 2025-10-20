-- {"query": "48011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 647} 
WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)) AS ModerationCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS LinkCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)) AS VoteCount
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= DATE('now', '-1 year')
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) AS VoteCount
    FROM
        Users u
    WHERE
        u.Id > 0
)
SELECT
    pe.PostId,
    pe.Title,
    pe.CreationDate AS PostCreationDate,
    pe.Score AS PostScore,
    pe.ViewCount AS PostViewCount,
    pe.AnswerCount AS PostAnswerCount,
    pe.CommentCount AS PostCommentCount,
    pe.ModerationCount AS PostModerationCount,
    pe.LinkCount AS PostLinkCount,
    pe.VoteCount AS PostVoteCount,
    ua.UserId,
    ua.DisplayName AS UserDisplayName,
    ua.Reputation AS UserReputation,
    ua.UserCreationDate,
    ua.BadgeCount AS UserBadgeCount,
    ua.PostCount AS UserPostCount,
    ua.CommentCount AS UserCommentCount,
    ua.VoteCount AS UserVoteCount
FROM
    PostEngagement pe
JOIN
    UserActivity ua ON pe.PostId = (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.UserId ORDER BY p.CreationDate DESC LIMIT 1)
ORDER BY
    pe.Score DESC, pe.ViewCount DESC
LIMIT 100;