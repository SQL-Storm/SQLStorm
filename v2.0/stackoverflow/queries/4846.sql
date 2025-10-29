WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostType,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostEditCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        (
            SELECT COUNT(DISTINCT b.Id)
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 1
        ) AS GoldBadgeCount,
        (
            SELECT COUNT(DISTINCT b.Id)
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 2
        ) AS SilverBadgeCount
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
LaggedPostCounts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        LAG(p.AnswerCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousAnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 5)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    GROUP BY p.Id
)
SELECT
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostEditCount,
    ua.UpVoteCount AS TotalUpVotes,
    ua.DownVoteCount AS TotalDownVotes,
    ua.CommentCount AS TotalComments,
    ua.GoldBadgeCount,
    ua.SilverBadgeCount,
    rp.PostId AS LatestQuestionId,
    rp.Title AS LatestQuestionTitle,
    rp.PostCreationDate AS LatestQuestionDate,
    lpc.Score AS LatestQuestionScore,
    lpc.AnswerCount AS LatestQuestionAnswerCount,
    lpc.PreviousPostScore AS PreviousQuestionScore,
    lpc.PreviousAnswerCount AS PreviousQuestionAnswerCount,
    pe.CommentCount AS LatestQuestionComments,
    pe.UpVoteCount AS LatestQuestionUpVotes,
    pe.DownVoteCount AS LatestQuestionDownVotes,
    pe.FavoriteCount AS LatestQuestionFavorites,
    pe.DuplicateLinkCount AS LatestQuestionDuplicateLinks,
    CASE
        WHEN ua.Reputation > 10000 THEN 'High Reputation'
        WHEN ua.Reputation BETWEEN 1000 AND 10000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationBracket,
    CASE WHEN ua.UserCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5' YEAR) THEN 'Long Term User' ELSE 'Newer User' END AS UserTenure,
    LOWER(SUBSTRING(ua.DisplayName FROM 1 FOR 3)) AS FirstThreeCharsDisplayName
FROM UserActivity ua
LEFT JOIN RankedPosts rp ON ua.UserId = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN LaggedPostCounts lpc ON rp.PostId = lpc.Id
LEFT JOIN PostEngagement pe ON rp.PostId = pe.PostId
WHERE ua.Reputation > 100 AND ua.DisplayName IS NOT NULL
GROUP BY
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostEditCount,
    ua.UpVoteCount,
    ua.DownVoteCount,
    ua.CommentCount,
    ua.GoldBadgeCount,
    ua.SilverBadgeCount,
    rp.PostId,
    rp.Title,
    rp.PostCreationDate,
    lpc.Score,
    lpc.AnswerCount,
    lpc.PreviousPostScore,
    lpc.PreviousAnswerCount,
    pe.CommentCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pe.FavoriteCount,
    pe.DuplicateLinkCount
ORDER BY ua.Reputation DESC, ua.UserCreationDate ASC
LIMIT 100;