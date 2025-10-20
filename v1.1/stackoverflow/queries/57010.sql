WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation
    ORDER BY
        (COUNT(p.Id) + COUNT(DISTINCT a.Id) + COUNT(DISTINCT c.Id) + COUNT(DISTINCT v.Id) + COUNT(DISTINCT b.Id)) DESC
    LIMIT 100
),
UserActivity AS (
    SELECT
        tu.UserId,
        MAX(p.LastActivityDate) AS LastActivityDate,
        MAX(p.CreationDate) AS LastPostCreationDate,
        MAX(c.CreationDate) AS LastCommentCreationDate,
        MAX(v.CreationDate) AS LastVoteCreationDate
    FROM
        TopUsers tu
    LEFT JOIN
        Posts p ON tu.UserId = p.OwnerUserId
    LEFT JOIN
        Comments c ON tu.UserId = c.UserId
    LEFT JOIN
        Votes v ON tu.UserId = v.UserId
    GROUP BY
        tu.UserId
),
UserMetrics AS (
    SELECT
        tu.UserId,
        tu.Reputation,
        ua.LastActivityDate,
        ua.LastPostCreationDate,
        ua.LastCommentCreationDate,
        ua.LastVoteCreationDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tu.UserId AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tu.UserId AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tu.UserId AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tu.UserId AND v.VoteTypeId = 2) AS UpVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = tu.UserId AND v.VoteTypeId = 3) AS DownVotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = tu.UserId) AND v.VoteTypeId = 2) AS UpVotesReceived,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = tu.UserId) AND v.VoteTypeId = 3) AS DownVotesReceived,
        DENSE_RANK() OVER (ORDER BY tu.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY ua.LastActivityDate DESC NULLS LAST) AS ActivityRank
    FROM
        TopUsers tu
    JOIN
        UserActivity ua ON tu.UserId = ua.UserId
)
SELECT
    um.UserId,
    um.Reputation,
    um.LastActivityDate,
    um.LastPostCreationDate,
    um.LastCommentCreationDate,
    um.LastVoteCreationDate,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    um.UpVotesGiven,
    um.DownVotesGiven,
    um.UpVotesReceived,
    um.DownVotesReceived,
    um.ReputationRank,
    um.ActivityRank
FROM
    UserMetrics um
ORDER BY
    um.ReputationRank,
    um.ActivityRank;