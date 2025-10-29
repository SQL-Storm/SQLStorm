WITH RECURSIVE UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id BETWEEN 100 AND 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostType,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(DISTINCT c.Id) AS CommentCountTotal,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS PostUpVotes,
        COALESCE(SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS PostDownVotes,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes pv ON p.Id = pv.PostId
    WHERE p.CreationDate >= DATE '2023-01-01'
    GROUP BY p.Id, p.Title, pt.Name, u.DisplayName, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate
),
RankedPosts AS (
    SELECT
        pe.PostId,
        pe.Title,
        pe.PostType,
        pe.OwnerDisplayName,
        pe.CreationDate,
        pe.Score,
        pe.ViewCount,
        pe.AnswerCount,
        pe.CommentCount,
        pe.FavoriteCount,
        pe.CommentCountTotal,
        pe.PostUpVotes,
        pe.PostDownVotes,
        pe.IsClosed,
        pe.IsCommunityOwned,
        ROW_NUMBER() OVER (ORDER BY pe.Score DESC, pe.ViewCount DESC) AS PostRankByScoreView,
        DENSE_RANK() OVER (PARTITION BY pe.PostType ORDER BY pe.FavoriteCount DESC) AS PostRankByTypeFavorite
    FROM PostEngagement pe
),
UserPostSummary AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate AS UserCreationDate,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.UpVoteCount,
        ua.DownVoteCount,
        COALESCE(SUM(rp.Score), 0) AS TotalScoreOfUserPosts,
        AVG(rp.ViewCount) AS AverageViewCountOfUserPosts,
        COUNT(DISTINCT CASE WHEN rp.IsClosed = 1 THEN rp.PostId ELSE NULL END) AS ClosedPostCount,
        STRING_AGG(rp.Title, ' | ' ORDER BY rp.CreationDate DESC) AS RecentPostTitles
    FROM UserActivity ua
    LEFT JOIN RankedPosts rp ON ua.DisplayName = rp.OwnerDisplayName
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.CreationDate, ua.PostCount, ua.QuestionCount, ua.AnswerCount, ua.UpVoteCount, ua.DownVoteCount
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.UserCreationDate,
    ups.PostCount,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.UpVoteCount,
    ups.DownVoteCount,
    ups.TotalScoreOfUserPosts,
    ups.AverageViewCountOfUserPosts,
    ups.ClosedPostCount,
    ups.RecentPostTitles,
    rp.PostId AS TopPostId,
    rp.Title AS TopPostTitle,
    rp.PostType AS TopPostType,
    rp.Score AS TopPostScore,
    rp.ViewCount AS TopPostViewCount,
    rp.PostRankByScoreView,
    rp.PostRankByTypeFavorite,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ups.UserId AND c.CreationDate > ups.UserCreationDate) AS CommentsAfterUserCreation,
    CASE
        WHEN ups.TotalScoreOfUserPosts IS NULL OR ups.TotalScoreOfUserPosts = 0 THEN 'No Posts'
        WHEN ups.TotalScoreOfUserPosts > 10000 THEN 'Legendary'
        WHEN ups.TotalScoreOfUserPosts > 5000 THEN 'Expert'
        ELSE 'Intermediate'
    END AS ReputationTierByPostScore,
    CASE
        WHEN ups.AnswerCount > ups.QuestionCount * 2 AND ups.AnswerCount > 10 THEN 'Answer Focused'
        WHEN ups.QuestionCount > ups.AnswerCount * 2 AND ups.QuestionCount > 10 THEN 'Question Focused'
        ELSE 'Balanced'
    END AS UserFocus
FROM UserPostSummary ups
LEFT JOIN RankedPosts rp ON ups.DisplayName = rp.OwnerDisplayName
WHERE ups.Reputation > 500
ORDER BY ups.Reputation DESC, ups.TotalScoreOfUserPosts DESC
LIMIT 100;