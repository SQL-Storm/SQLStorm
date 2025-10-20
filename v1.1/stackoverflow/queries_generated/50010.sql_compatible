WITH TagSpecificPosts AS (
    SELECT Id, OwnerUserId, ParentId, PostTypeId, Score, CreationDate
    FROM Posts
    WHERE Tags LIKE '%<sql>%' OR Id IN (SELECT ParentId FROM Posts WHERE Tags LIKE '%<sql>%')
),
UserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score AS PostScore,
        p.CreationDate AS PostCreationDate,
        p_q.CreationDate AS QuestionCreationDate
    FROM Users u
    JOIN TagSpecificPosts p ON u.Id = p.OwnerUserId
    LEFT JOIN TagSpecificPosts p_q ON p.ParentId = p_q.Id AND p_q.PostTypeId = 1
    WHERE u.Reputation > 1000 AND p.OwnerUserId IS NOT NULL
),
AggregatedStats AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        COUNT(PostId) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(PostScore) AS TotalScore,
        AVG(PostScore) AS AverageScore,
        MIN(PostCreationDate) AS FirstPostDate,
        MAX(PostCreationDate) AS LastPostDate,
        AVG(CASE WHEN PostTypeId = 2 THEN EXTRACT(EPOCH FROM (PostCreationDate - QuestionCreationDate)) ELSE NULL END) AS AvgTimeToAnswer
    FROM UserContributions
    GROUP BY UserId, DisplayName, Reputation, UserCreationDate
),
BadgeAndVoteDetails AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
WithPercentiles AS (
    SELECT
        a.*,
        bvd.TotalVotesCast,
        bvd.UpvotesCast,
        bvd.GoldBadges,
        bvd.SilverBadges,
        (a.TotalScore * 0.4 + a.AnswerCount * 10 + bvd.UpvotesCast * 0.1 + bvd.GoldBadges * 100 + bvd.SilverBadges * 20) /
            (EXTRACT(EPOCH FROM (a.LastPostDate - a.FirstPostDate)) / 86400.0 + 1) AS WeightedActivityScore,
        NTILE(100) OVER (ORDER BY a.Reputation DESC) AS ReputationPercentile
    FROM AggregatedStats a
    JOIN BadgeAndVoteDetails bvd ON a.UserId = bvd.UserId
)
SELECT
    w.DisplayName,
    w.Reputation,
    w.TotalPosts,
    w.QuestionCount,
    w.AnswerCount,
    w.TotalScore,
    w.AverageScore,
    w.AvgTimeToAnswer,
    w.TotalVotesCast,
    w.UpvotesCast,
    w.GoldBadges,
    w.SilverBadges,
    w.WeightedActivityScore,
    w.ReputationPercentile,
    RANK() OVER (PARTITION BY ((w.ReputationPercentile - 1) / 10) ORDER BY w.TotalScore DESC) AS RankWithinReputationDecile
FROM WithPercentiles w
WHERE
    w.AnswerCount > w.QuestionCount
    AND w.AnswerCount > 10
    AND (w.LastPostDate - w.FirstPostDate) > INTERVAL '30 day'
ORDER BY
    w.WeightedActivityScore DESC, w.Reputation DESC
LIMIT 100;