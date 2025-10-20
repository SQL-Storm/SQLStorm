WITH PostInteraction AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN 1 ELSE 0 END) AS TitleEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeleteVoteCount
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS UserBodyEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4) THEN 1 ELSE 0 END) AS UserTitleEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS UserCloseVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS UserReopenVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS UserDeleteVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UserUndeleteVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UserUpVoteGivenCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS UserDownVoteGivenCount
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
)
SELECT
    pi.PostId,
    pt.Name AS PostType,
    pi.PostCreationDate,
    pi.CommentCount,
    pi.VoteCount,
    pi.BodyEditCount,
    pi.TitleEditCount,
    pi.CloseVoteCount,
    pi.ReopenVoteCount,
    pi.DeleteVoteCount,
    pi.UndeleteVoteCount,
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.UserViews,
    ua.UserUpVotes,
    ua.UserDownVotes,
    ua.BadgeCount,
    ua.UserBodyEditCount,
    ua.UserTitleEditCount,
    ua.UserCloseVoteCount,
    ua.UserReopenVoteCount,
    ua.UserDeleteVoteCount,
    ua.UserUndeleteVoteCount,
    ua.UserUpVoteGivenCount,
    ua.UserDownVoteGivenCount,
    (pi.CommentCount + pi.VoteCount + pi.BodyEditCount + pi.TitleEditCount + pi.CloseVoteCount + pi.ReopenVoteCount + pi.DeleteVoteCount + pi.UndeleteVoteCount) AS TotalPostInteractions,
    (ua.UserBodyEditCount + ua.UserTitleEditCount + ua.UserCloseVoteCount + ua.UserReopenVoteCount + ua.UserDeleteVoteCount + ua.UserUndeleteVoteCount + ua.UserUpVoteGivenCount + ua.UserDownVoteGivenCount) AS TotalUserActivity
FROM
    PostInteraction pi
JOIN
    PostTypes pt ON pi.PostTypeId = pt.Id
JOIN
    UserActivity ua ON pi.OwnerUserId = ua.UserId
WHERE
    pi.PostCreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
ORDER BY
    TotalPostInteractions DESC, TotalUserActivity DESC, ua.Reputation DESC
LIMIT 1000;