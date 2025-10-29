WITH PostInteractions AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        COUNT(DISTINCT c.Id) AS CommentCountTotal,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequenceByOwner,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER(PARTITION BY p.OwnerUserId) AS AvgUserPostScore
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.FavoriteCount, p.AnswerCount, p.CommentCount, p.ClosedDate, pt.Name
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        MAX(pi.PostCreationDate) AS LastPostDate,
        COUNT(DISTINCT pi.PostId) AS TotalPosts,
        SUM(pi.PostScore) AS TotalScoreFromPosts,
        AVG(pi.PostViewCount) AS AvgPostViewCount,
        SUM(CASE WHEN pi.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pi.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgesEarned,
        SUM(CASE WHEN pi.PostSequenceByOwner <= 3 THEN 1 ELSE 0 END) AS RecentThreePosts,
        COALESCE(MAX(pi.AvgUserPostScore), 0) AS AveragePostScore,
        CASE
            WHEN COUNT(DISTINCT pi.PostId) > 0 THEN
                CAST(SUM(CASE WHEN pi.PostTypeId = 2 THEN 1 ELSE 0 END) AS DOUBLE PRECISION) / COUNT(DISTINCT pi.PostId)
            ELSE 0
        END AS AnswerRate
    FROM Users u
    JOIN PostInteractions pi ON u.Id = pi.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostLaggedScore AS (
    SELECT
        Id,
        OwnerUserId,
        Score,
        CreationDate,
        LAG(Score, 1, 0) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate) AS PreviousPostScore,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY CreationDate DESC) AS RowNumDesc
    FROM Posts
    WHERE PostTypeId = 1
),
TopUsersWithHighRatedAnswers AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.AnswerRate,
        ue.AveragePostScore,
        ue.AnswerCount,
        COUNT(DISTINCT p.Id) AS NumberOfHighlyRatedAnswers
    FROM UserEngagement ue
    JOIN Posts p ON ue.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 2
      AND p.Score >= 10
      AND ue.AnswerRate > 0.5
    GROUP BY
        ue.UserId, ue.DisplayName, ue.Reputation, ue.AnswerRate, ue.AveragePostScore, ue.AnswerCount
    HAVING COUNT(DISTINCT p.Id) > 5
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalPosts,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.AnswerRate,
    ue.AveragePostScore,
    ue.BadgeCount,
    ue.BadgesEarned,
    ue.UserViews,
    ue.UserTotalUpVotes,
    ue.UserTotalDownVotes,
    pls.PreviousPostScore AS ScoreOfPreviousQuestion,
    COALESCE(tuhra.NumberOfHighlyRatedAnswers, 0) AS HighlyRatedAnswerCount,
    CASE
        WHEN ue.Reputation > 100000 THEN 'Expert'
        WHEN ue.Reputation > 50000 THEN 'Senior'
        WHEN ue.Reputation > 10000 THEN 'Intermediate'
        WHEN ue.Reputation > 1000 THEN 'Beginner'
        ELSE 'Novice'
    END AS ReputationLevel,
    UPPER(SUBSTR(ue.DisplayName, 1, 1)) || SUBSTR(ue.DisplayName, 2) AS FormattedDisplayName,
    CASE
        WHEN ue.LastPostDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR) THEN 'Inactive'
        WHEN ue.LastPostDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' MONTH) THEN 'Lapsed'
        ELSE 'Active'
    END AS UserActivityStatus,
    CASE
        WHEN EXISTS (SELECT 1 FROM Badges WHERE UserId = ue.UserId AND Name LIKE '%Great Answer%') THEN 'HasGreatAnswerBadge'
        ELSE 'NoGreatAnswerBadge'
    END AS AnswerBadgeStatus,
    ue.TotalScoreFromPosts * ue.AnswerCount AS WeightedScore,
    CAST(ue.TotalPosts AS DOUBLE PRECISION) / (CAST(ue.UserViews AS DOUBLE PRECISION) + 1) AS PostToViewRatio
FROM UserEngagement ue
LEFT JOIN PostLaggedScore pls ON ue.UserId = pls.OwnerUserId AND pls.RowNumDesc = 1
LEFT JOIN TopUsersWithHighRatedAnswers tuhra ON ue.UserId = tuhra.UserId
WHERE ue.Reputation > 1000
  AND ue.AnswerCount > 5
  AND ue.AnswerRate > 0.3
ORDER BY
    ue.Reputation DESC, ue.AnswerRate DESC, ue.TotalScoreFromPosts * ue.AnswerCount DESC
LIMIT 100;