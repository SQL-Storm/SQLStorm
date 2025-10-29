WITH PostVoteScores AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) DESC, p.CreationDate DESC) AS rn_user_upvotes,
        DENSE_RANK() OVER (ORDER BY COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) DESC) AS dr_global_upvotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 5)
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(COUNT(DISTINCT pvs.PostId), 0) AS TotalPosts,
        COALESCE(SUM(pvs.UpVoteCount), 0) AS TotalUpVotesReceived,
        COALESCE(SUM(pvs.DownVoteCount), 0) AS TotalDownVotesReceived,
        COALESCE(SUM(pvs.FavoriteCount), 0) AS TotalFavoritesReceived,
        COALESCE(MAX(pvs.PostCreationDate), DATE '1970-01-01') AS LatestPostDate,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1 ELSE 0 END AS HasWebsite,
        CASE WHEN u.Location LIKE '%USA%' OR u.Location LIKE '%United States%' THEN 1 ELSE 0 END AS IsUSLocation,
        'User_' || CAST(u.Id AS VARCHAR) AS UniqueUserIdString,
        CASE
            WHEN u.Views > 1000000 THEN 'High'
            WHEN u.Views > 100000 THEN 'Medium'
            ELSE 'Low'
        END AS ViewSegment
    FROM Users u
    LEFT JOIN PostVoteScores pvs ON u.Id = pvs.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.WebsiteUrl, u.Location, u.Views
),
UserBadgeCounts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
)
SELECT
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalPosts,
    ue.TotalUpVotesReceived,
    ue.TotalDownVotesReceived,
    ue.TotalFavoritesReceived,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ue.HasWebsite,
    ue.IsUSLocation,
    ue.ViewSegment,
    pvs.dr_global_upvotes AS GlobalUpvoteRank,
    CASE
        WHEN ue.TotalPosts = 0 THEN 0.0
        ELSE CAST(ue.TotalUpVotesReceived AS REAL) / ue.TotalPosts
    END AS AvgUpvotesPerPost,
    CASE
        WHEN ue.TotalPosts = 0 THEN 0.0
        ELSE CAST(ue.TotalDownVotesReceived AS REAL) / ue.TotalPosts
    END AS AvgDownvotesPerPost,
    ue.UniqueUserIdString,
    COALESCE(u_older.DisplayName, 'No Older User') AS OlderUserDisplayName,
    CASE WHEN ue.LatestPostDate > (SELECT MAX(CreationDate) FROM Posts WHERE PostTypeId = 1) THEN 'Recent' ELSE 'Older' END AS PostActivityStatus,
    u_older.Id AS OlderUserId,
    u_older.Reputation AS OlderUserReputation
FROM UserEngagement ue
LEFT JOIN UserBadgeCounts ubc ON ue.UserId = ubc.UserId
LEFT JOIN PostVoteScores pvs ON ue.UserId = pvs.OwnerUserId AND pvs.rn_user_upvotes = 1
LEFT JOIN Users u_older ON ue.UserId > u_older.Id AND u_older.Reputation > ue.Reputation
WHERE ue.Reputation > 1000 AND ue.TotalPosts > 10
GROUP BY
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalPosts,
    ue.TotalUpVotesReceived,
    ue.TotalDownVotesReceived,
    ue.TotalFavoritesReceived,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ue.HasWebsite,
    ue.IsUSLocation,
    ue.ViewSegment,
    pvs.dr_global_upvotes,
    ue.UniqueUserIdString,
    ue.LatestPostDate,
    u_older.DisplayName,
    u_older.Id,
    u_older.Reputation
HAVING ue.TotalUpVotesReceived > ue.TotalDownVotesReceived * 2
ORDER BY ue.Reputation DESC, ue.TotalUpVotesReceived DESC
LIMIT 100;