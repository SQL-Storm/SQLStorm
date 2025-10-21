WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        (SELECT COUNT(*) FROM Badges WHERE UserId = u.Id) AS BadgeCount,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id) AS PostCount,
        (SELECT COUNT(*) FROM Comments WHERE UserId = u.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id AND VoteTypeId = 2) AS UpVoteGivenCount,
        (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id AND VoteTypeId = 3) AS DownVoteGivenCount,
        (SELECT SUM(Score) FROM Posts WHERE OwnerUserId = u.Id) AS TotalPostScore,
        (SELECT SUM(Score) FROM Comments WHERE UserId = u.Id) AS TotalCommentScore,
        u.CreationDate,
        u.LastAccessDate
    FROM Users u
    WHERE u.Reputation > 1000
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS ActualCommentCount,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND Cast(VoteTypeId AS INTEGER) = 2) AS UpVotesOnPost,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND Cast(VoteTypeId AS INTEGER) = 3) AS DownVotesOnPost,
        (SELECT COUNT(*) FROM PostLinks WHERE PostId = p.Id OR RelatedPostId = p.Id) AS LinkCount,
        p.ClosedDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= DATE 'now' - INTERVAL '1 year'
),
CombinedMetrics AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Views,
        ua.UserUpVotes,
        ua.UserDownVotes,
        ua.BadgeCount,
        ua.PostCount,
        ua.CommentCount AS UserCommentCount,
        ua.UpVoteGivenCount,
        ua.DownVoteGivenCount,
        ua.TotalPostScore,
        ua.TotalCommentScore,
        ua.CreationDate AS UserCreationDate,
        ua.LastAccessDate,
        SUM(CASE WHEN pe.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pe.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(pe.PostScore) AS TotalScoreOfUserPosts,
        SUM(pe.PostViewCount) AS TotalViewsOfUserPosts,
        SUM(pe.FavoriteCount) AS TotalFavoritesOfUserPosts,
        AVG(pe.PostScore) AS AvgPostScore,
        AVG(pe.PostViewCount) AS AvgPostViewCount,
        AVG(pe.ActualCommentCount) AS AvgPostCommentCount,
        MAX(pe.PostCreationDate) AS LatestPostDate
    FROM UserActivity ua
    LEFT JOIN PostEngagement pe ON ua.UserId = pe.OwnerUserId
    GROUP BY
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Views,
        ua.UserUpVotes,
        ua.UserDownVotes,
        ua.BadgeCount,
        ua.PostCount,
        ua.CommentCount,
        ua.UpVoteGivenCount,
        ua.DownVoteGivenCount,
        ua.TotalPostScore,
        ua.TotalCommentScore,
        ua.CreationDate,
        ua.LastAccessDate
)
SELECT
    cm.UserId,
    cm.DisplayName,
    cm.Reputation,
    cm.QuestionCount,
    cm.AnswerCount,
    cm.PostCount,
    cm.UserCommentCount,
    cm.UpVoteGivenCount,
    cm.DownVoteGivenCount,
    cm.TotalPostScore,
    cm.TotalCommentScore,
    cm.TotalScoreOfUserPosts,
    cm.TotalViewsOfUserPosts,
    cm.TotalFavoritesOfUserPosts,
    cm.AvgPostScore,
    cm.AvgPostViewCount,
    cm.AvgPostCommentCount,
    cm.LatestPostDate,
    cm.UserCreationDate,
    cm.LastAccessDate,
    cm.Views AS UserTotalViews,
    cm.UserUpVotes AS UserTotalUpVotes,
    cm.UserDownVotes AS UserTotalDownVotes,
    cm.BadgeCount,
    CASE
        WHEN cm.TotalScoreOfUserPosts > 10000 THEN 'High Performing'
        WHEN cm.TotalScoreOfUserPosts > 1000 THEN 'Mid Performing'
        ELSE 'Low Performing'
    END AS PerformanceTier
FROM CombinedMetrics cm
WHERE cm.PostCount > 0
ORDER BY cm.Reputation DESC, cm.TotalScoreOfUserPosts DESC, cm.LatestPostDate DESC;