WITH UserPostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.Score) AS MaxScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopPostPerUser AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
AggregatedVotes AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 4 THEN 1 END) AS OffensiveVotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3,4)
    GROUP BY v.PostId
),
UserComments AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 50), '; ') AS SampleComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(ups.QuestionCount, 0) AS Questions,
        COALESCE(ups.AnswerCount, 0) AS Answers,
        COALESCE(ups.AvgScore, 0) AS AvgPostScore,
        COALESCE(ups.TotalViews, 0) AS TotalPostViews,
        COALESCE(ubs.TotalBadges, 0) AS Badges,
        COALESCE(tp.Title, 'No Questions') AS TopQuestionTitle,
        COALESCE(tp.Score, 0) AS TopQuestionScore,
        COALESCE(uc.CommentCount, 0) AS CommentsMade,
        COALESCE(uc.SampleComments, 'None') AS SampleComments,
        (COALESCE(ups.QuestionCount, 0) + COALESCE(ups.AnswerCount, 0)) * (1 + COALESCE(ups.AvgScore, 0)/100) AS ComputedActivityScore,
        RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(ups.TotalViews, 0) DESC) AS ReputationRank,
        CASE 
            WHEN ups.QuestionCount IS NULL THEN 'No Posts'
            WHEN ups.QuestionCount > ups.AnswerCount THEN 'Questioner'
            ELSE 'Answerer'
        END AS UserType,
        EXISTS (
            SELECT 1 FROM AggregatedVotes av 
            WHERE av.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id) 
            AND av.OffensiveVotes > 0
        ) AS HasOffensivePost
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    LEFT JOIN TopPostPerUser tp ON u.Id = tp.OwnerUserId AND tp.Rn = 1
    LEFT JOIN UserComments uc ON u.Id = uc.UserId
    WHERE u.Reputation > 0
        AND (
            COALESCE(ups.QuestionCount, 0) > 0 
            OR COALESCE(ubs.TotalBadges, 0) > 0 
            OR EXISTS (
                SELECT 1 FROM Posts p2 
                WHERE p2.OwnerUserId = u.Id 
                AND p2.ClosedDate IS NULL 
                AND p2.Score > 10
            )
        )
)
SELECT *
FROM (
    SELECT *
    FROM TopUsers
    ORDER BY ReputationRank
    LIMIT 100
) tu

UNION ALL

SELECT 
    NULL AS UserId,
    'Summary: Top 100 Users' AS DisplayName,
    SUM(COALESCE(tu.Questions, 0)) AS Questions,
    SUM(COALESCE(tu.Answers, 0)) AS Answers,
    AVG(COALESCE(tu.AvgPostScore, 0)) AS AvgPostScore,
    SUM(COALESCE(tu.TotalPostViews, 0)) AS TotalPostViews,
    SUM(COALESCE(tu.Badges, 0)) AS Badges,
    'Aggregate' AS TopQuestionTitle,
    MAX(tu.TopQuestionScore) AS TopQuestionScore,
    SUM(tu.CommentsMade) AS CommentsMade,
    'Aggregated' AS SampleComments,
    SUM(tu.ComputedActivityScore) AS ComputedActivityScore,
    0 AS ReputationRank,
    'Aggregate' AS UserType,
    CASE WHEN SUM(CASE WHEN tu.HasOffensivePost THEN 1 ELSE 0 END) > 0 THEN TRUE ELSE FALSE END AS HasOffensivePost
FROM (
    SELECT *
    FROM TopUsers
    ORDER BY ReputationRank
    LIMIT 100
) tu;