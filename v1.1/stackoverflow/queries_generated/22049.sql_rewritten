-- {"query": "22049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 979} 
WITH UserQuestionStats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(p.Id) AS TotalQuestions,
           AVG(p.Score) AS AvgQuestionScore,
           SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedQuestions,
           STRING_AGG(DISTINCT COALESCE(substring(LOWER(p.Tags), 2, LENGTH(p.Tags)-2), ''), ', ') AS TagList
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserAnswerStats AS (
    SELECT u.Id AS UserId,
           COUNT(p.Id) AS TotalAnswers,
           AVG(p.Score) AS AvgAnswerScore,
           COUNT(DISTINCT p.ParentId) AS DistinctQuestionsAnswered
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 2
    GROUP BY u.Id
),
BadgeStats AS (
    SELECT b.UserId,
           COUNT(*) AS TotalBadges,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
CommentActivity AS (
    SELECT c.UserId,
           COUNT(c.Id) AS TotalComments,
           AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    GROUP BY c.UserId
),
UserVotes AS (
    SELECT u.Id AS UserId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3)
    GROUP BY u.Id
),
RankedUsers AS (
    SELECT uqs.*,
           uas.TotalAnswers,
           uas.AvgAnswerScore,
           uas.DistinctQuestionsAnswered,
           bs.TotalBadges,
           bs.GoldBadges,
           bs.LatestBadgeDate,
           ca.TotalComments,
           ca.AvgCommentLength,
           uv.UpVotesReceived,
           uv.DownVotesReceived,
           ROW_NUMBER() OVER (ORDER BY uqs.Reputation DESC) AS ReputationRank,
           RANK() OVER (ORDER BY COALESCE(uas.TotalAnswers, 0) + COALESCE(uqs.TotalQuestions, 0) DESC) AS ActivityRank,
           uqs.Reputation + COALESCE(uqs.TotalQuestions * 10, 0) + COALESCE(uas.TotalAnswers * 5, 0) + COALESCE(bs.GoldBadges * 100, 0) AS EngagementScore
    FROM UserQuestionStats uqs
    FULL OUTER JOIN UserAnswerStats uas ON uqs.UserId = uas.UserId
    LEFT JOIN BadgeStats bs ON uqs.UserId = bs.UserId
    LEFT JOIN CommentActivity ca ON uqs.UserId = ca.UserId
    LEFT JOIN UserVotes uv ON uqs.UserId = uv.UserId
),
TopUsers AS (
    SELECT *
    FROM RankedUsers
    WHERE ReputationRank <= 500
      AND (TotalQuestions > 0 OR TotalAnswers > 0)
      AND EXISTS (
          SELECT 1
          FROM Comments c
          WHERE c.UserId = RankedUsers.UserId
            AND LENGTH(c.Text) > 20
      )
      AND EngagementScore > (SELECT AVG(EngagementScore) FROM RankedUsers WHERE EngagementScore IS NOT NULL)
)
(
    SELECT tu.UserId,
           tu.DisplayName,
           tu.TotalQuestions,
           tu.TotalAnswers,
           tu.TagList,
           tu.EngagementScore,
           'Questions' AS Type,
           ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.EngagementScore DESC) AS SubRank
    FROM TopUsers tu
    WHERE tu.TotalQuestions > tu.TotalAnswers
)
UNION ALL
(
    SELECT tu.UserId,
           tu.DisplayName,
           tu.TotalQuestions,
           tu.TotalAnswers,
           NULL AS TagList,
           tu.EngagementScore,
           'Answers' AS Type,
           ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.EngagementScore DESC) AS SubRank
    FROM TopUsers tu
    WHERE tu.TotalAnswers >= tu.TotalQuestions
)
ORDER BY EngagementScore DESC, UserId, SubRank;