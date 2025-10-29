WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(rp.Score) AS AvgPostScore,
        SUM(rp.ViewCount) AS TotalViews,
        SUM(rp.CommentCount) AS TotalComments,
        MAX(rp.CreationDate) AS LastPostDate
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    WHERE rp.rn <= 50
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
PostAttributes AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        pt.Name AS PostTypeName,
        CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END AS QuestionTitle,
        CASE WHEN p.PostTypeId = 2 THEN SUBSTRING(p.Body FROM 1 FOR 100) ELSE NULL END AS AnswerSnippet,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        CASE WHEN p.ClosedDate IS NOT NULL THEN CAST((EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 86400) AS INTEGER) ELSE NULL END AS DaysToClose,
        LOWER(REPLACE(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>', '')) AS FormattedTags,
        p.CreationDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserPostJoin AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserUpVotes,
        ue.UserDownVotes,
        pa.PostId,
        pa.PostTypeName,
        pa.QuestionTitle,
        pa.AnswerSnippet,
        pa.Score,
        pa.ViewCount,
        pa.FavoriteCount,
        pa.ClosedDate,
        pa.IsCommunityOwned,
        pa.DaysToClose,
        pa.FormattedTags,
        pa.CreationDate
    FROM UserEngagement ue
    JOIN PostAttributes pa ON ue.UserId = pa.OwnerUserId
),
TagMetrics AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        COUNT(DISTINCT upj.UserId) AS DistinctUsersTagging,
        AVG(upj.Score) AS AvgTagScore,
        SUM(upj.FavoriteCount) AS TotalTagFavorites
    FROM Tags t
    JOIN UserPostJoin upj ON upj.FormattedTags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName, t.Count
),
LaggedScores AS (
    SELECT
        upj.PostId,
        upj.UserId,
        upj.Score,
        upj.CreationDate,
        LAG(upj.Score, 1, 0) OVER (PARTITION BY upj.UserId ORDER BY upj.CreationDate) AS PreviousPostScore
    FROM UserPostJoin upj
),
FinalResult AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserUpVotes,
        ue.UserDownVotes,
        ue.TotalPosts,
        ue.QuestionCount,
        ue.AnswerCount,
        ue.AvgPostScore,
        ue.TotalViews,
        ue.TotalComments,
        ue.LastPostDate,
        COUNT(DISTINCT CASE WHEN pa.IsCommunityOwned = 1 THEN pa.PostId END) AS CommunityOwnedPosts,
        SUM(CASE WHEN pa.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts,
        AVG(pa.DaysToClose) FILTER (WHERE pa.DaysToClose IS NOT NULL) AS AvgDaysToClose,
        SUM(CASE WHEN pa.FavoriteCount > 0 THEN 1 ELSE 0 END) AS PostsWithFavorites,
        STRING_AGG(DISTINCT tm.TagName, ', ') AS TopTags,
        COUNT(DISTINCT CASE WHEN ls.Score > ls.PreviousPostScore THEN ls.PostId END) AS PostsWithScoreIncrease,
        SUM(CASE WHEN pa.PostTypeName = 'Question' AND pa.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestions,
        SUM(CASE WHEN pa.PostTypeName = 'Answer' AND pa.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers
    FROM UserEngagement ue
    LEFT JOIN PostAttributes pa ON ue.UserId = pa.OwnerUserId
    LEFT JOIN TagMetrics tm ON pa.FormattedTags LIKE '%' || tm.TagName || '%'
    LEFT JOIN LaggedScores ls ON pa.PostId = ls.PostId AND ue.UserId = ls.UserId
    GROUP BY
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserUpVotes,
        ue.UserDownVotes,
        ue.TotalPosts,
        ue.QuestionCount,
        ue.AnswerCount,
        ue.AvgPostScore,
        ue.TotalViews,
        ue.TotalComments,
        ue.LastPostDate
)
SELECT
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.UserUpVotes,
    fr.UserDownVotes,
    fr.TotalPosts,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.AvgPostScore,
    fr.TotalViews,
    fr.TotalComments,
    fr.LastPostDate,
    fr.CommunityOwnedPosts,
    fr.ClosedPosts,
    fr.AvgDaysToClose,
    fr.PostsWithFavorites,
    fr.TopTags,
    fr.PostsWithScoreIncrease,
    fr.ClosedQuestions,
    fr.PositiveScoreAnswers,
    CASE
        WHEN fr.Reputation > 100000 THEN 'Legendary'
        WHEN fr.Reputation > 50000 THEN 'Titan'
        WHEN fr.Reputation > 10000 THEN 'Expert'
        WHEN fr.Reputation > 1000 THEN 'Experienced'
        WHEN fr.Reputation > 100 THEN 'Novice'
        ELSE 'New User'
    END AS ReputationTier,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = fr.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = fr.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = fr.UserId AND b.Class = 3) AS BronzeBadges,
    (SELECT MAX(CreationDate) FROM Comments c WHERE c.UserId = fr.UserId) AS LastCommentDate,
    CASE
        WHEN fr.UserUpVotes > fr.UserDownVotes * 2 THEN 'High Polarity'
        WHEN fr.UserDownVotes > fr.UserUpVotes * 2 THEN 'Low Polarity'
        ELSE 'Balanced Polarity'
    END AS VotePolarity
FROM FinalResult fr
WHERE fr.TotalPosts > 10
ORDER BY fr.Reputation DESC, fr.TotalPosts DESC
LIMIT 100;