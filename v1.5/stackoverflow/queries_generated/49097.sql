-- {"query": "49097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1776} 

WITH UserPostAggregates AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(p.Score) AS TotalOwnedPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViewCount,
        COUNT(DISTINCT p.Id) AS TotalPostsOwnedCount,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers
    FROM
        Posts p
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.OwnerUserId
),
UserAnswerAcceptanceImpact AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(p.Score) AS ScoreFromAcceptedAnswers,
        COUNT(p.Id) AS AcceptedAnswersCount
    FROM
        Posts p
    INNER JOIN
        Posts q ON p.Id = q.AcceptedAnswerId
    WHERE
        p.PostTypeId = 2 -- Only answers can be accepted
        AND q.PostTypeId = 1 -- Only questions can have accepted answers
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
UserQuestionAcceptedAnswerImpact AS (
    SELECT
        q.OwnerUserId AS UserId,
        SUM(a.Score) AS ScoreOfAcceptedAnswersForOwnQuestions,
        COUNT(DISTINCT q.Id) AS OwnQuestionsWithAcceptedAnswersCount
    FROM
        Posts q -- The question
    INNER JOIN
        Posts a ON q.AcceptedAnswerId = a.Id -- The accepted answer
    WHERE
        q.PostTypeId = 1 -- Must be a question
        AND q.AcceptedAnswerId IS NOT NULL
        AND q.OwnerUserId IS NOT NULL
    GROUP BY
        q.OwnerUserId
),
UserBadgeMetrics AS (
    SELECT
        b.UserId,
        SUM(CASE b.Class
                WHEN 1 THEN 100 -- Gold
                WHEN 2 THEN 50  -- Silver
                WHEN 3 THEN 10  -- Bronze
                ELSE 0
            END) AS WeightedBadgeScore,
        COUNT(b.Id) AS TotalBadgesCount
    FROM
        Badges b
    GROUP BY
        b.UserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS TotalCommentScore
    FROM
        Comments c
    WHERE
        c.UserId IS NOT NULL
    GROUP BY
        c.UserId
),
UserPostEditActivity AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalEditsCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS ContentEditsCount
    FROM
        PostHistory ph
    WHERE
        ph.UserId IS NOT NULL
    GROUP BY
        ph.UserId
),
UserVotingActivity AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE NULL END) AS FavoritesMadeCount
    FROM
        Votes v
    WHERE
        v.UserId IS NOT NULL
        AND v.VoteTypeId IN (2, 3, 5)
    GROUP BY
        v.UserId
),
UserTagContributionDiversity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS UniqueTagsContributed
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions have tags
        AND p.OwnerUserId IS NOT NULL
        AND p.Tags IS NOT NULL
        AND LENGTH(p.Tags) > 2 -- Ensure tags string is not empty or just "<>"
    GROUP BY
        p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(upa.TotalOwnedPostScore, 0) AS TotalPostsScore,
    COALESCE(uaai.ScoreFromAcceptedAnswers, 0) AS UserAcceptedAnswerScore,
    COALESCE(uqai.ScoreOfAcceptedAnswersForOwnQuestions, 0) AS QuestionAcceptedAnswerScore,
    COALESCE(ubm.WeightedBadgeScore, 0) AS WeightedBadgeScore,
    COALESCE(uca.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(up.ContentEditsCount, 0) AS TotalContentEdits,
    COALESCE(uv.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(uv.DownVotesGiven, 0) AS DownVotesGiven,
    COALESCE(utcd.UniqueTagsContributed, 0) AS UniqueTagsContributed,
    (
        u.Reputation * 0.15
        + COALESCE(upa.TotalOwnedPostScore, 0) * 0.5
        + COALESCE(uaai.ScoreFromAcceptedAnswers, 0) * 1.8
        + COALESCE(uqai.ScoreOfAcceptedAnswersForOwnQuestions, 0) * 0.9
        + COALESCE(ubm.WeightedBadgeScore, 0) * 0.015
        + COALESCE(uca.TotalCommentsMade, 0) * 0.1
        + COALESCE(up.ContentEditsCount, 0) * 0.08
        + COALESCE(upa.TotalQuestionViewCount, 0) * 0.000008
        + COALESCE(uv.UpVotesGiven, 0) * 0.0012
        - COALESCE(uv.DownVotesGiven, 0) * 0.0006
        + COALESCE(utcd.UniqueTagsContributed, 0) * 0.03
        -- Recency factor: more recent activity gets a boost, scaled by months
        + (CASE WHEN u.LastAccessDate IS NOT NULL THEN
              (EXTRACT(EPOCH FROM (NOW() - u.LastAccessDate)) / (3600 * 24 * 30.5)) * -0.00002
          ELSE 0 END)
        -- Bonus for consistent activity
        + (CASE WHEN (upa.TotalPostsOwnedCount > 100 AND ubm.TotalBadgesCount > 50) THEN 50 ELSE 0 END)
    ) AS CalculatedInfluenceScore
FROM
    Users u
LEFT JOIN UserPostAggregates upa ON u.Id = upa.UserId
LEFT JOIN UserAnswerAcceptanceImpact uaai ON u.Id = uaai.UserId
LEFT JOIN UserQuestionAcceptedAnswerImpact uqai ON u.Id = uqai.UserId
LEFT JOIN UserBadgeMetrics ubm ON u.Id = ubm.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserPostEditActivity up ON u.Id = up.UserId
LEFT JOIN UserVotingActivity uv ON u.Id = uv.UserId
LEFT JOIN UserTagContributionDiversity utcd ON u.Id = utcd.UserId
ORDER BY
    CalculatedInfluenceScore DESC, u.Reputation DESC, u.CreationDate ASC
LIMIT 100;
