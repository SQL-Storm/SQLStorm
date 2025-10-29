WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        SUM(CASE WHEN p_votes.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScoreReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Votes p_votes ON p.Id = p_votes.PostId AND p_votes.VoteTypeId IN (2, 3, 4, 5)
    GROUP BY u.Id
),
UserPostMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS UserQuestionCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion,
        MAX(p.ViewCount) AS MaxQuestionViewCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS TotalEditsMadeByOwner,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        AVG(CASE WHEN p.PostTypeId = 1 THEN LENGTH(p.Body) ELSE NULL END) AS AvgQuestionBodyLength,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName FROM 1 FOR 20), ';') AS UserTagsSummary
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Tags t ON (
        p.Tags IS NOT NULL
        AND LENGTH(p.Tags) > 2
        AND t.TagName IN (
            SELECT TRIM(tag)
            FROM (
                SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')) AS tag
            ) sub
        )
    )
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
OffensiveActionParticipants AS (
    SELECT v.UserId AS ParticipantUserId FROM Votes v WHERE v.VoteTypeId = 4 AND v.UserId IS NOT NULL
    UNION
    SELECT p.OwnerUserId AS ParticipantUserId FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE v.VoteTypeId = 4 AND p.OwnerUserId IS NOT NULL
),
ComplexQuestionMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        STRING_AGG(DISTINCT COALESCE(crt.Name, 'No Reason'), ',') AS QuestionClosureReasons,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN ph_edit.PostHistoryTypeId IN (4,5,6) AND ph_edit.UserId IS NOT NULL AND ph_edit.UserId != p.OwnerUserId THEN ph_edit.UserId END) AS UniqueEditorsCount,
        MAX(CASE WHEN ph_edit.PostHistoryTypeId IN (4,5,6) AND ph_edit.UserId IS NOT NULL AND ph_edit.UserId != p.OwnerUserId THEN ph_edit.CreationDate END) AS LatestEditDateByOther
    FROM Posts p
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON (ph_close.Comment IS NOT NULL AND ph_close.Comment ~ '^\d+$' AND CAST(ph_close.Comment AS INTEGER) = crt.Id)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId
)
SELECT
    u.Id AS UserID,
    u.DisplayName AS UserName,
    COALESCE(u.Location, 'Undisclosed') AS UserLocation,
    u.Reputation,
    COALESCE(uas.TotalPosts, 0) AS TotalPosts,
    COALESCE(uas.TotalComments, 0) AS TotalComments,
    COALESCE(upm.UserQuestionCount, 0) AS UserQuestionCount,
    COALESCE(upm.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(ub.TotalBadges, 0) AS TotalBadges,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    (u.UpVotes - u.DownVotes) AS NetUserVotesGiven,
    COALESCE(uas.TotalUpvotesReceivedOnPosts, 0) AS TotalPostUpvotesReceived,
    COALESCE(uas.TotalCommentScoreReceived, 0) AS TotalCommentScoreReceived,
    (
        SELECT COUNT(DISTINCT c.Id)
        FROM Comments c
        JOIN Posts p_q ON c.PostId = p_q.Id
        WHERE c.UserId = u.Id
          AND p_q.OwnerUserId = u.Id
          AND p_q.PostTypeId = 1
          AND c.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months')
    ) AS RecentOwnQuestionComments,
    (
        SELECT AVG(ans.Score)
        FROM Posts q_main
        JOIN Posts ans ON q_main.AcceptedAnswerId = ans.Id
        WHERE q_main.OwnerUserId = u.Id AND q_main.PostTypeId = 1 AND q_main.AcceptedAnswerId IS NOT NULL
    ) AS AvgAcceptedAnswerScore,
    RANK() OVER (PARTITION BY COALESCE(u.Location, 'GLOBAL') ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankInLocation,
    AVG(u.Reputation) OVER (ORDER BY u.CreationDate ROWS BETWEEN 100 PRECEDING AND 1 PRECEDING) AS AvgReputationLast100Users,
    COALESCE((
        SELECT regexp_replace(subdomain_match, '/.*$', '') FROM (SELECT regexp_matches(COALESCE(u.WebsiteUrl, ''), '^(?:https?://)?([^/]+)') AS m, (regexp_matches(COALESCE(u.WebsiteUrl, ''), '^(?:https?://)?([^/]+)'))[1] AS subdomain_match) sub
    ), 'No Website') AS WebsiteDomain,
    CASE
        WHEN u.Reputation >= 10000 AND COALESCE(ub.GoldBadges, 0) >= 5 THEN 'Elite Contributor'
        WHEN u.Reputation >= 5000 AND COALESCE(ub.SilverBadges, 0) >= 10 THEN 'Senior Participant'
        WHEN u.Reputation >= 1000 AND COALESCE(upm.UserQuestionCount, 0) >= 10 AND COALESCE(upm.AvgAnswersPerQuestion, 0) >= 2 THEN 'Active Questioner'
        WHEN u.Reputation >= 500 AND COALESCE(uas.TotalComments, 0) >= 50 THEN 'Engaged Commenter'
        WHEN u.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') AND u.Reputation >= 200 THEN 'Rising Star'
        ELSE 'Casual User'
    END AS UserCategory,
    (
        u.Reputation * 0.1
        + COALESCE(u.Views, 0) * 0.01
        + COALESCE(uas.TotalPosts, 0) * 0.5
        + COALESCE(uas.TotalComments, 0) * 0.3
        + COALESCE(upm.TotalQuestionScore, 0) * 0.8
        + COALESCE(ub.TotalBadges, 0) * 10
        + COALESCE(ub.GoldBadges, 0) * 50
    ) AS EngagementScore,
    COALESCE((
        SELECT AVG(p_linked.Score)
        FROM Posts p_linked
        JOIN PostLinks pl_inner ON p_linked.Id = pl_inner.PostId
        JOIN ComplexQuestionMetrics cqm_inner ON p_linked.Id = cqm_inner.PostId
        WHERE p_linked.OwnerUserId = u.Id
          AND p_linked.PostTypeId = 1
          AND pl_inner.LinkTypeId = 1
          AND cqm_inner.QuestionClosureReasons LIKE '%No Reason%'
        GROUP BY p_linked.OwnerUserId
    ), 0) AS AvgScoreOfUnclosedLinkedQuestions,
    (COALESCE(upm.TotalEditsMadeByOwner, 0) > 0 AND u.AboutMe IS NOT NULL AND (LOWER(u.AboutMe) LIKE '%developer%' OR LOWER(u.AboutMe) LIKE '%programmer%')) AS IsDevAndEditor,
    (ub.LatestBadgeDate > u.LastAccessDate AND COALESCE(ub.SilverBadges, 0) > 5) AS RecentHighBadgeActivity,
    AggregatedCQM.UserClosureReasons,
    COALESCE(AggregatedCQM.TotalLinkedPostsForUser, 0) AS TotalLinkedPostsForUser,
    COALESCE(AggregatedCQM.TotalUniqueEditorsOnUserQuestions, 0) AS TotalUniqueEditorsOnUserQuestions,
    AggregatedCQM.LatestQuestionEditByOther
FROM Users u
LEFT JOIN UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN UserPostMetrics upm ON u.Id = upm.UserId
LEFT JOIN UserBadgeSummary ub ON u.Id = ub.UserId
LEFT JOIN (
    SELECT
        UserId,
        STRING_AGG(DISTINCT QuestionClosureReasons, ';') AS UserClosureReasons,
        SUM(LinkedPostsCount) AS TotalLinkedPostsForUser,
        SUM(UniqueEditorsCount) AS TotalUniqueEditorsOnUserQuestions,
        MAX(LatestEditDateByOther) AS LatestQuestionEditByOther
    FROM ComplexQuestionMetrics
    GROUP BY UserId
) AS AggregatedCQM ON u.Id = AggregatedCQM.UserId
WHERE u.Reputation >= 100
  AND u.CreationDate BETWEEN CAST('2010-01-01' AS DATE) AND CAST('2023-01-01' AS DATE)
  AND u.LastAccessDate BETWEEN CAST('2022-01-01' AS DATE) AND CAST('2023-06-01' AS DATE)
  AND u.DisplayName IS NOT NULL AND LENGTH(u.DisplayName) > 3
  AND NOT EXISTS (
      SELECT 1
      FROM OffensiveActionParticipants oap
      WHERE oap.ParticipantUserId = u.Id
  )
  AND (
      (COALESCE(u.Views, 0) > 5000 AND COALESCE(u.UpVotes, 0) > 1000 AND COALESCE(upm.AvgAnswersPerQuestion, 0) > 1.5)
      OR
      (COALESCE(upm.UserQuestionCount, 0) >= 20 AND COALESCE(ub.GoldBadges, 0) >= 1)
      OR
      (LOWER(COALESCE(u.Location, '')) LIKE '%london%' AND COALESCE(uas.TotalComments, 0) >= 100)
  )
ORDER BY EngagementScore DESC, u.Reputation DESC, u.CreationDate ASC
LIMIT 1000;