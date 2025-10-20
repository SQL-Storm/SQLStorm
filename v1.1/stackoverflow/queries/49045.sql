WITH TopPerformingTags AS (
    SELECT
        tag AS TagName,
        COUNT(DISTINCT p.Id) AS QuestionCountInTag,
        SUM(p.Score) AS TotalTagScore,
        AVG(p.ViewCount) AS AverageTagQuestionViewCount
    FROM Posts p,
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.Tags <> ''
    GROUP BY tag
    HAVING COUNT(DISTINCT p.Id) > 50
       AND SUM(p.Score) > 200
    ORDER BY SUM(p.Score) DESC, COUNT(DISTINCT p.Id) DESC
    LIMIT 500
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT q.Id) AS TotalQuestionsOwned,
        SUM(q.Score) AS TotalQuestionScoreOwned,
        AVG(q.ViewCount) AS AvgQuestionViewCountOwned,
        SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        SUM(COALESCE(q.FavoriteCount, 0)) AS TotalFavoriteCountOnQuestions,
        COUNT(DISTINCT a.Id) AS TotalAnswersOwned,
        SUM(a.Score) AS TotalAnswerScoreOwned,
        AVG(ans.Score) FILTER (WHERE ans.Id = q.AcceptedAnswerId) AS AvgScoreOfAcceptedAnswersGiven,
        AVG(q_accepted.Score) FILTER (WHERE q.AcceptedAnswerId = q_accepted.Id) AS AvgScoreOfAcceptedAnswersOnTheirQuestions,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6,7,8,9) AND ph.UserId = u.Id THEN ph.Id END) AS SelfEditEvents,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13,14,15,19,20) AND ph.UserId = u.Id THEN ph.Id END) AS ModeratorActionEvents,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade
    FROM Users u
    LEFT JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Posts q_accepted ON q.AcceptedAnswerId = q_accepted.Id AND q_accepted.PostTypeId = 2
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Posts ans ON u.Id = ans.OwnerUserId AND ans.PostTypeId = 2
        AND ans.Id IN (SELECT p2.AcceptedAnswerId FROM Posts p2 WHERE p2.AcceptedAnswerId IS NOT NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT q.Id) + COUNT(DISTINCT a.Id) > 10
),
UserTagContributionSummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT tag) AS UniqueTopTagsContributed,
        SUM(p.Score) AS ScoreInTopTagsQuestions,
        COUNT(p.Id) AS QuestionsInTopTags,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswerInTopTags
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    JOIN TopPerformingTags tpt ON TRUE
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
      AND tag = tpt.TagName
    GROUP BY u.Id
),
UserBadgeOverview AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.UserLastAccessDate,
    uas.TotalQuestionsOwned,
    uas.TotalQuestionScoreOwned,
    uas.AvgQuestionViewCountOwned,
    uas.QuestionsWithAcceptedAnswers,
    uas.TotalFavoriteCountOnQuestions,
    uas.TotalAnswersOwned,
    uas.TotalAnswerScoreOwned,
    COALESCE(uas.AvgScoreOfAcceptedAnswersGiven, 0.0) AS AvgScoreOfAcceptedAnswersGiven,
    COALESCE(uas.AvgScoreOfAcceptedAnswersOnTheirQuestions, 0.0) AS AvgScoreOfAcceptedAnswersOnTheirQuestions,
    uas.SelfEditEvents,
    uas.ModeratorActionEvents,
    uas.TotalCommentsMade,
    COALESCE(utcs.UniqueTopTagsContributed, 0) AS UniqueTopTagsContributed,
    COALESCE(utcs.ScoreInTopTagsQuestions, 0) AS ScoreInTopTagsQuestions,
    COALESCE(utcs.QuestionsInTopTags, 0) AS QuestionsInTopTags,
    COALESCE(utcs.QuestionsWithAcceptedAnswerInTopTags, 0) AS QuestionsWithAcceptedAnswerInTopTags,
    COALESCE(ubo.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubo.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubo.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubo.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubo.TagBasedBadges, 0) AS TagBasedBadges,
    RANK() OVER (
        ORDER BY
            uas.Reputation DESC,
            (uas.TotalQuestionScoreOwned + uas.TotalAnswerScoreOwned * 1.5 + COALESCE(utcs.ScoreInTopTagsQuestions, 0) * 2) DESC,
            (uas.QuestionsWithAcceptedAnswers * 5 + COALESCE(utcs.QuestionsWithAcceptedAnswerInTopTags, 0) * 10) DESC,
            (COALESCE(ubo.GoldBadges, 0) * 100 + COALESCE(ubo.SilverBadges, 0) * 10 + COALESCE(ubo.BronzeBadges, 0)) DESC,
            uas.SelfEditEvents DESC,
            (uas.TotalCommentsMade + uas.ModeratorActionEvents * 2) DESC,
            uas.AvgQuestionViewCountOwned DESC
    ) AS UserEngagementRank
FROM UserActivitySummary uas
LEFT JOIN UserTagContributionSummary utcs ON uas.UserId = utcs.UserId
LEFT JOIN UserBadgeOverview ubo ON uas.UserId = ubo.UserId
WHERE uas.Reputation > 10000
  AND uas.TotalQuestionsOwned > 10
  AND uas.TotalAnswersOwned > 5
  AND uas.SelfEditEvents > 5
  AND uas.UserLastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
ORDER BY UserEngagementRank
LIMIT 100;