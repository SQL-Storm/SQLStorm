WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesCount,
        COUNT(DISTINCT p.Id) AS PostsCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        COUNT(DISTINCT b.Id) AS BadgesCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
)
SELECT 
    ua.UserId,
    u.DisplayName,
    ua.UpVotesCount,
    ua.DownVotesCount,
    ua.PostsCount,
    ua.CommentsCount,
    ua.BadgesCount,
    u.Reputation,
    u.Views,
    (ua.UpVotesCount * 10 - ua.DownVotesCount * 2 + ua.PostsCount * 5 + ua.CommentsCount * 3 + ua.BadgesCount * 15) AS ActivityScore
FROM UserActivity ua
JOIN Users u ON ua.UserId = u.Id
WHERE u.Reputation > 1000
GROUP BY
    ua.UserId,
    u.DisplayName,
    ua.UpVotesCount,
    ua.DownVotesCount,
    ua.PostsCount,
    ua.CommentsCount,
    ua.BadgesCount,
    u.Reputation,
    u.Views
ORDER BY ActivityScore DESC
LIMIT 100;