-- {"query": "50092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1071} 
WITH TaggedQuestions AS (
    -- Find all questions with a specific tag created in the last 5 years
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        p.Score AS QuestionScore
    FROM
        Posts AS p
    WHERE
        p.PostTypeId = 1 -- Question
        AND p.Tags LIKE '%<sql>%'
        AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year')
),
UserActivityInTag AS (
    -- Aggregate stats for users who ANSWERED questions in the tag
    SELECT
        a.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS AvgAnswerTimeSeconds,
        SUM(CASE WHEN a.Id = q_posts.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM
        Posts AS a
    JOIN
        TaggedQuestions AS q ON a.ParentId = q.Id
    JOIN
        Posts AS q_posts ON q.Id = q_posts.Id
    WHERE
        a.PostTypeId = 2 -- Answer
        AND a.OwnerUserId IS NOT NULL
    GROUP BY
        a.OwnerUserId
),
UserReputationRanking AS (
    -- Rank all users by reputation to find their percentile
    SELECT
        Id,
        Reputation,
        NTILE(100) OVER (ORDER BY Reputation DESC) as ReputationPercentile
    FROM
        Users
),
UserBadgeAndVoteStats AS (
    -- Aggregate badge and voting stats for each user
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id
)
-- Final selection and scoring
SELECT
    u.DisplayName,
    u.Reputation,
    urr.ReputationPercentile,
    COALESCE(uat.AnswerCount, 0) AS AnswersInTag,
    COALESCE(uat.TotalAnswerScore, 0) AS ScoreFromAnswers,
    COALESCE(uat.AcceptedAnswers, 0) AS AcceptedAnswersInTag,
    COALESCE(ubvs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubvs.GoldBadges, 0) AS GoldBadges,
    ubvs.LastCommentDate,
    -- Calculate a complex 'Influence Score'
    (
        (COALESCE(uat.TotalAnswerScore, 0) * 2.5) +
        (COALESCE(uat.AcceptedAnswers, 0) * 25) +
        (u.Reputation / 100.0) +
        (COALESCE(ubvs.GoldBadges, 0) * 50) -
        -- Penalize users who take longer to answer, measured in hours
        (COALESCE(uat.AvgAnswerTimeSeconds, 0) / 3600.0)
    ) * (1 + (COALESCE(ubvs.TotalUpVotesGiven, 0) / (NULLIF(ubvs.TotalDownVotesGiven, 0) * 5.0 + 1000.0))) AS InfluenceScore
FROM
    Users AS u
JOIN
    UserActivityInTag AS uat ON u.Id = uat.OwnerUserId
JOIN
    UserReputationRanking AS urr ON u.Id = urr.Id
JOIN
    UserBadgeAndVoteStats AS ubvs ON u.Id = ubvs.UserId
WHERE
    u.Reputation > 5000 -- Only consider users with significant reputation
    AND uat.AnswerCount > 10 -- And who have answered a minimum number of questions in the tag
    AND u.CreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year') -- And are not new users
ORDER BY
    InfluenceScore DESC,
    u.Reputation DESC
LIMIT 200;