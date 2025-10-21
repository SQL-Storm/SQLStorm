-- {"query": "50093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 885} 

WITH UserQuestionStats AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalQuestions,
        AVG(Score) AS AvgQuestionScore,
        MIN(CreationDate) AS FirstQuestionDate
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
    HAVING COUNT(Id) > 10
),
UserAnswerStats AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalAnswers,
        AVG(Score) AS AvgAnswerScore,
        SUM(CASE WHEN p_ans.Id = p_q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Posts p_ans
    JOIN Posts p_q ON p_ans.ParentId = p_q.Id
    WHERE p_ans.PostTypeId = 2 AND p_ans.OwnerUserId IS NOT NULL
    GROUP BY p_ans.OwnerUserId
),
TopTagsPerUser AS (
    SELECT
        p.OwnerUserId,
        t.TagName,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) as rn
    FROM Posts p,
         LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
UserEngagement AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        qs.TotalQuestions,
        qs.AvgQuestionScore,
        COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
        CAST(COALESCE(ans.AcceptedAnswers, 0) AS REAL) / GREATEST(ans.TotalAnswers, 1) AS AcceptedAnswerRatio,
        EXTRACT(EPOCH FROM (NOW() - qs.FirstQuestionDate))/86400 AS TenureDays,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpVotesGiven,
        (SELECT ttu.TagName FROM TopTagsPerUser ttu WHERE ttu.OwnerUserId = u.Id AND ttu.rn = 1) AS PrimaryTag
    FROM Users u
    JOIN UserQuestionStats qs ON u.Id = qs.OwnerUserId
    LEFT JOIN UserAnswerStats ans ON u.Id = ans.OwnerUserId
    WHERE u.Reputation > 50000 AND u.UpVotes > u.DownVotes
)
SELECT
    ue.DisplayName,
    ue.Reputation,
    ue.PrimaryTag,
    ue.TotalQuestions,
    ue.TotalAnswers,
    CAST(ue.AvgQuestionScore AS DECIMAL(10, 2)) AS AvgQScore,
    CAST(ue.AvgAnswerScore AS DECIMAL(10, 2)) AS AvgAnsScore,
    CAST(ue.AcceptedAnswerRatio * 100 AS DECIMAL(5, 2)) AS AcceptRatePercent,
    ue.GoldBadges,
    ue.TotalComments,
    ue.TotalUpVotesGiven,
    CAST(ue.Reputation / GREATEST(ue.TenureDays, 1) AS DECIMAL(10, 2)) AS DailyReputationGain
FROM UserEngagement ue
WHERE ue.GoldBadges > 0 AND ue.PrimaryTag IS NOT NULL
ORDER BY DailyReputationGain DESC, ue.Reputation DESC
LIMIT 100;

