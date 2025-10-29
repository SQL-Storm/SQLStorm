-- {"query": "1318.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3248} 

WITH UserActivitySummary AS (
    -- Summarize user activity: total posts, comments, total upvotes/downvotes given/received on posts
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven, -- User giving upvotes
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven, -- User giving downvotes
        SUM(CASE WHEN p_votes.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts, -- Upvotes on their posts
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScoreReceived -- Score received on their comments
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId -- Votes given by user
    LEFT JOIN Votes p_votes ON p.Id = p_votes.PostId AND p_votes.VoteTypeId IN (2, 3, 4, 5) -- Votes on posts owned by user
    GROUP BY u.Id
),
UserPostMetrics AS (
    -- Aggregate metrics for posts owned by users, focusing on questions and their tags/edits
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS UserQuestionCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion,
        MAX(p.ViewCount) AS MaxQuestionViewCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS TotalEditsMadeByOwner,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        AVG(LENGTH(p.Body)) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionBodyLength,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 20), ';') FILTER (WHERE t.TagName IS NOT NULL) AS UserTagsSummary
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Tags t ON t.TagName IN (
        SELECT unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
        WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    )
    WHERE p.PostTypeId = 1 -- Only consider questions
    GROUP BY p.OwnerUserId
),
UserBadgeSummary AS (
    -- Summarize badge counts per user by class
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
    -- Identify users who have either cast an offensive vote OR owned a post that received an offensive vote
    SELECT v.UserId AS ParticipantUserId FROM Votes v WHERE v.VoteTypeId = 4 AND v.UserId IS NOT NULL
    UNION
    SELECT p.OwnerUserId AS ParticipantUserId FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE v.VoteTypeId = 4 AND p.OwnerUserId IS NOT NULL
),
ComplexQuestionMetrics AS (
    -- CTE to find complex question metrics like closure reason, related posts and unique editors
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        STRING_AGG(DISTINCT COALESCE(crt.Name, 'No Reason'), ',') AS QuestionClosureReasons,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT ph_edit.UserId) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4,5,6) AND ph_edit.UserId != p.OwnerUserId) AS UniqueEditorsCount,
        MAX(ph_edit.CreationDate) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4,5,6) AND ph_edit.UserId != p.OwnerUserId) AS LatestEditDateByOther
    FROM Posts p
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post closed history
    LEFT JOIN CloseReasonTypes crt ON ph_close.Comment ~ '^\d+$' AND ph_close.Comment::smallint = crt.Id -- Ensure Comment is numeric for cast
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1 -- Linked posts
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId -- All edit history
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

    -- Correlated Subquery: Count of user's comments on their own *questions* in the last 6 months
    (
        SELECT COUNT(DISTINCT c.Id)
        FROM Comments c
        JOIN Posts p_q ON c.PostId = p_q.Id
        WHERE c.UserId = u.Id
          AND p_q.OwnerUserId = u.Id
          AND p_q.PostTypeId = 1
          AND c.CreationDate >= NOW() - INTERVAL '6 months'
    ) AS RecentOwnQuestionComments,

    -- Scalar Subquery: Average score of accepted answers for user's questions
    (
        SELECT AVG(ans.Score)
        FROM Posts q_main
        JOIN Posts ans ON q_main.AcceptedAnswerId = ans.Id
        WHERE q_main.OwnerUserId = u.Id AND q_main.PostTypeId = 1 AND q_main.AcceptedAnswerId IS NOT NULL
    ) AS AvgAcceptedAnswerScore,

    -- Window Function 1: Rank users by reputation within their location
    RANK() OVER (PARTITION BY COALESCE(u.Location, 'GLOBAL') ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankInLocation,

    -- Window Function 2: Moving average of reputation over user creation date for the 100 most recently created users (excluding current)
    AVG(u.Reputation) OVER (ORDER BY u.CreationDate ROWS BETWEEN 100 PRECEDING AND 1 PRECEDING) AS AvgReputationLast100Users,

    -- String Expression: Extract first part of website URL if exists, otherwise indicate no URL
    COALESCE(SUBSTRING(u.WebsiteUrl FROM '^(?:https?://)?([^/]+)'), 'No Website') AS WebsiteDomain,

    -- Complex CASE expression for User Category based on reputation, badges, and post activity
    CASE
        WHEN u.Reputation >= 10000 AND COALESCE(ub.GoldBadges, 0) >= 5 THEN 'Elite Contributor'
        WHEN u.Reputation >= 5000 AND COALESCE(ub.SilverBadges, 0) >= 10 THEN 'Senior Participant'
        WHEN u.Reputation >= 1000 AND COALESCE(upm.UserQuestionCount, 0) >= 10 AND COALESCE(upm.AvgAnswersPerQuestion, 0) >= 2 THEN 'Active Questioner'
        WHEN u.Reputation >= 500 AND COALESCE(uas.TotalComments, 0) >= 50 THEN 'Engaged Commenter'
        WHEN u.CreationDate >= NOW() - INTERVAL '1 year' AND u.Reputation >= 200 THEN 'Rising Star'
        ELSE 'Casual User'
    END AS UserCategory,

    -- More complicated calculation: 'Engagement Score'
    (
        u.Reputation * 0.1
        + COALESCE(u.Views, 0) * 0.01
        + COALESCE(uas.TotalPosts, 0) * 0.5
        + COALESCE(uas.TotalComments, 0) * 0.3
        + COALESCE(upm.TotalQuestionScore, 0) * 0.8
        + COALESCE(ub.TotalBadges, 0) * 10
        + COALESCE(ub.GoldBadges, 0) * 50
    ) AS EngagementScore,

    -- Average post score for user's questions with at least one linked post and no closure reasons
    COALESCE((
        SELECT AVG(p_linked.Score)
        FROM Posts p_linked
        JOIN PostLinks pl_inner ON p_linked.Id = pl_inner.PostId
        JOIN ComplexQuestionMetrics cqm_inner ON p_linked.Id = cqm_inner.PostId
        WHERE p_linked.OwnerUserId = u.Id
          AND p_linked.PostTypeId = 1
          AND pl_inner.LinkTypeId = 1
          AND cqm_inner.QuestionClosureReasons LIKE '%No Reason%' -- Exclude closed posts
        GROUP BY p_linked.OwnerUserId
    ), 0) AS AvgScoreOfUnclosedLinkedQuestions,

    -- NULL logic and complex predicate: Users who have edited their own posts AND have a non-null AboutMe containing "developer" or "programmer"
    (COALESCE(upm.TotalEditsMadeByOwner, 0) > 0 AND u.AboutMe IS NOT NULL AND (LOWER(u.AboutMe) LIKE '%developer%' OR LOWER(u.AboutMe) LIKE '%programmer%')) AS IsDevAndEditor,

    -- Check if user's latest badge date is after their last access date AND they have more than 5 silver badges
    (ub.LatestBadgeDate > u.LastAccessDate AND COALESCE(ub.SilverBadges, 0) > 5) AS RecentHighBadgeActivity,

    -- Aggregated Question Closure Reasons for the user
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
        STRING_AGG(DISTINCT QuestionClosureReasons, ';') FILTER (WHERE QuestionClosureReasons IS NOT NULL) AS UserClosureReasons,
        SUM(LinkedPostsCount) AS TotalLinkedPostsForUser,
        SUM(UniqueEditorsCount) AS TotalUniqueEditorsOnUserQuestions,
        MAX(LatestEditDateByOther) AS LatestQuestionEditByOther
    FROM ComplexQuestionMetrics
    GROUP BY UserId
) AS AggregatedCQM ON u.Id = AggregatedCQM.UserId

WHERE u.Reputation >= 100
  AND u.CreationDate BETWEEN '2010-01-01' AND '2023-01-01'
  AND u.LastAccessDate BETWEEN '2022-01-01' AND '2023-06-01' -- Active users in a recent period
  AND u.DisplayName IS NOT NULL AND LENGTH(u.DisplayName) > 3
  AND NOT EXISTS (
      -- Exclude users who are participants in offensive actions
      SELECT 1
      FROM OffensiveActionParticipants oap
      WHERE oap.ParticipantUserId = u.Id
  )
  -- Another complex predicate involving nested conditions for user activity
  AND (
      (COALESCE(u.Views, 0) > 5000 AND COALESCE(u.UpVotes, 0) > 1000 AND COALESCE(upm.AvgAnswersPerQuestion, 0) > 1.5)
      OR
      (COALESCE(upm.UserQuestionCount, 0) >= 20 AND COALESCE(ub.GoldBadges, 0) >= 1)
      OR
      (LOWER(u.Location) LIKE '%london%' AND COALESCE(uas.TotalComments, 0) >= 100)
  )

ORDER BY EngagementScore DESC, u.Reputation DESC, u.CreationDate ASC
LIMIT 1000;
