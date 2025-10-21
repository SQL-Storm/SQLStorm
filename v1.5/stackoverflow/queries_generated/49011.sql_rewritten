-- {"query": "49011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2300} 
WITH UserQuestionActivity AS (
    -- Select questions by a specific tag and active within a recent period, joining with users
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS QuestionId,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount AS QuestionAnswerCount,
        p.AcceptedAnswerId,
        p.CreationDate AS QuestionCreationDate
    FROM
        Posts AS p
    WHERE
        p.PostTypeId = 1 -- Questions
        AND p.Tags LIKE '%<javascript>%' -- Target specific tag
        AND p.CreationDate >= '2020-01-01' -- Filter by recent activity
        AND p.OwnerUserId IS NOT NULL
),
UserAnswerActivity AS (
    -- Select answers provided by users who are active question askers, within the same period
    SELECT
        a.OwnerUserId AS UserId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.ParentId AS AnsweredQuestionId,
        a.CreationDate AS AnswerCreationDate
    FROM
        Posts AS a
    WHERE
        a.PostTypeId = 2 -- Answers
        AND a.CreationDate >= '2020-01-01'
        AND a.OwnerUserId IS NOT NULL
),
UserAggregateQuestionMetrics AS (
    -- Aggregate key metrics for questions asked by each user
    SELECT
        uqa.UserId,
        COUNT(uqa.QuestionId) AS TotalQuestionsAsked,
        SUM(uqa.QuestionScore) AS TotalQuestionScore,
        AVG(uqa.QuestionScore) AS AvgQuestionScore,
        SUM(uqa.QuestionViewCount) AS TotalQuestionViews,
        AVG(uqa.QuestionViewCount) AS AvgQuestionViewCount,
        SUM(CASE WHEN uqa.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersOnQuestionsRatioNumerator
    FROM
        UserQuestionActivity AS uqa
    GROUP BY
        uqa.UserId
    HAVING
        COUNT(uqa.QuestionId) >= 5 -- Minimum number of questions
        AND SUM(uqa.QuestionScore) >= 50 -- Minimum total question score
),
UserAggregateAnswerMetrics AS (
    -- Aggregate key metrics for answers provided by each user
    SELECT
        uaa.UserId,
        COUNT(uaa.AnswerId) AS TotalAnswersGiven,
        SUM(uaa.AnswerScore) AS TotalAnswerScore,
        AVG(uaa.AnswerScore) AS AvgAnswerScore
    FROM
        UserAnswerActivity AS uaa
    GROUP BY
        uaa.UserId
    HAVING
        COUNT(uaa.AnswerId) >= 10 -- Minimum number of answers
        AND SUM(uaa.AnswerScore) >= 100 -- Minimum total answer score
),
TopUserQuestionEngagement AS (
    -- Identify each user's top 3 questions based on a combined score (score + view count)
    SELECT
        uqa.UserId,
        uqa.QuestionId,
        uqa.QuestionScore,
        uqa.QuestionViewCount,
        uqa.QuestionAnswerCount,
        RANK() OVER (PARTITION BY uqa.UserId ORDER BY uqa.QuestionScore DESC, uqa.QuestionViewCount DESC) AS QuestionRank
    FROM
        UserQuestionActivity AS uqa
    INNER JOIN
        UserAggregateQuestionMetrics AS uaqm ON uqa.UserId = uaqm.UserId
),
TopQuestionsCommentsAndEdits AS (
    -- Calculate average comment score and total edit count for the top questions of users
    SELECT
        tuqe.UserId,
        tuqe.QuestionId,
        AVG(c.Score) AS AvgQuestionCommentScore,
        COUNT(DISTINCT ph.Id) AS QuestionEditCount
    FROM
        TopUserQuestionEngagement AS tuqe
    LEFT JOIN
        Comments AS c ON tuqe.QuestionId = c.PostId
    LEFT JOIN
        PostHistory AS ph ON tuqe.QuestionId = ph.PostId
    WHERE
        tuqe.QuestionRank <= 3 -- Focus on top 3 questions per user
        AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit/Rollback Title, Body, Tags
    GROUP BY
        tuqe.UserId, tuqe.QuestionId
),
UserBadgeSummary AS (
    -- Count gold badges related to the target tag for each user
    SELECT
        b.UserId,
        COUNT(b.Id) AS GoldTagBadges
    FROM
        Badges AS b
    WHERE
        b.Class = 1 -- Gold badges
        AND b.TagBased = TRUE
        AND b.Name = 'javascript' -- Specific tag badge
    GROUP BY
        b.UserId
),
AnswererReputationOnUserQuestions AS (
    -- Calculate the average reputation of users who answered the questions of our target question authors
    SELECT
        q.UserId AS QuestionAuthorId,
        AVG(ans_u.Reputation) AS AvgAnswererReputation
    FROM
        UserQuestionActivity AS q
    INNER JOIN
        UserAnswerActivity AS ans ON q.QuestionId = ans.AnsweredQuestionId
    INNER JOIN
        Users AS ans_u ON ans.UserId = ans_u.Id
    GROUP BY
        q.UserId
),
UserVoteDistributionOnAnswers AS (
    -- Analyze the distribution of vote types on answers given by the target users
    SELECT
        uaa.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnAnswers,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnAnswers,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedByOriginatorVotesOnAnswers
    FROM
        UserAnswerActivity AS uaa
    INNER JOIN
        Votes AS v ON uaa.AnswerId = v.PostId
    GROUP BY
        uaa.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    uaqm.TotalQuestionsAsked,
    uaqm.TotalQuestionScore,
    uaqm.AvgQuestionScore,
    uaqm.TotalQuestionViews,
    CAST(uaqm.AcceptedAnswersOnQuestionsRatioNumerator AS DECIMAL(10,2)) / uaqm.TotalQuestionsAsked AS AcceptedAnswerRatio,
    uaam.TotalAnswersGiven,
    uaam.TotalAnswerScore,
    uaam.AvgAnswerScore,
    COALESCE(ubs.GoldTagBadges, 0) AS GoldTagBadgesCount,
    COALESCE(ars.AvgAnswererReputation, 0) AS AvgAnswererReputation,
    COALESCE(uvda.UpVotesOnAnswers, 0) AS TotalUpVotesOnAnswers,
    COALESCE(uvda.DownVotesOnAnswers, 0) AS TotalDownVotesOnAnswers,
    COALESCE(uvda.AcceptedByOriginatorVotesOnAnswers, 0) AS TotalAcceptedVotesOnAnswers,
    SUM(COALESCE(tqce.AvgQuestionCommentScore, 0)) / COUNT(DISTINCT tqce.QuestionId) AS AvgTopQuestionCommentScore,
    SUM(COALESCE(tqce.QuestionEditCount, 0)) AS TotalTopQuestionEditCount,
    (
        uaqm.TotalQuestionScore * 0.30 -- Weight for question score
        + uaqm.TotalQuestionViews * 0.01 -- Weight for question views
        + (CAST(uaqm.AcceptedAnswersOnQuestionsRatioNumerator AS DECIMAL(10,2)) / uaqm.TotalQuestionsAsked) * 50 -- Weight for accepted answer ratio
        + uaam.TotalAnswerScore * 0.20 -- Weight for answer score
        + COALESCE(ubs.GoldTagBadges, 0) * 25 -- Weight for gold tag badges
        + COALESCE(ars.AvgAnswererReputation, 0) * 0.02 -- Weight for answerer reputation
        + COALESCE(uvda.UpVotesOnAnswers, 0) * 0.05 -- Weight for total upvotes on answers
        - COALESCE(uvda.DownVotesOnAnswers, 0) * 0.10 -- Penalty for downvotes on answers
        + SUM(COALESCE(tqce.QuestionEditCount, 0)) * 1 -- Weight for edits on top questions
    ) AS CalculatedUserImpactScore
FROM
    Users AS u
INNER JOIN
    UserAggregateQuestionMetrics AS uaqm ON u.Id = uaqm.UserId
INNER JOIN
    UserAggregateAnswerMetrics AS uaam ON u.Id = uaam.UserId
LEFT JOIN
    UserBadgeSummary AS ubs ON u.Id = ubs.UserId
LEFT JOIN
    AnswererReputationOnUserQuestions AS ars ON u.Id = ars.QuestionAuthorId
LEFT JOIN
    UserVoteDistributionOnAnswers AS uvda ON u.Id = uvda.UserId
LEFT JOIN
    TopQuestionsCommentsAndEdits AS tqce ON u.Id = tqce.UserId
WHERE
    u.Reputation >= 1000 -- Filter users by a minimum reputation
    AND u.Id IS NOT NULL -- Ensure valid user IDs
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    uaqm.TotalQuestionsAsked, uaqm.TotalQuestionScore, uaqm.AvgQuestionScore, uaqm.TotalQuestionViews,
    uaqm.AcceptedAnswersOnQuestionsRatioNumerator, uaam.TotalAnswersGiven, uaam.TotalAnswerScore, uaam.AvgAnswerScore,
    ubs.GoldTagBadges, ars.AvgAnswererReputation, uvda.UpVotesOnAnswers, uvda.DownVotesOnAnswers, uvda.AcceptedByOriginatorVotesOnAnswers
ORDER BY
    CalculatedUserImpactScore DESC, u.Reputation DESC
LIMIT 50;