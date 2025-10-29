-- {"query": "1349.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2931} 

WITH UserReputationRank AS (
    -- Ranks users by reputation within their creation year and calculates reputation decile.
    -- Also provides average reputation for users within the same reported location.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC, u.Id) AS AnnualRepRank,
        NTILE(10) OVER (ORDER BY u.Reputation DESC) AS ReputationDecile,
        AVG(u.Reputation) OVER (PARTITION BY COALESCE(u.Location, 'Unknown')) AS AvgReputationInLocation
    FROM Users AS u
    WHERE u.Reputation > 0 AND u.AccountId IS NOT NULL
),
PostCommentVotesAggregate AS (
    -- Aggregates comment counts, upvote/downvote counts for each post.
    -- Uses a window function to look at the score of the previous post by the same owner.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount, -- UpMod votes
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount, -- DownMod votes
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVoteCount, -- AcceptedByOriginator
        MAX(v.CreationDate) AS LastVoteDate,
        MIN(c.CreationDate) AS FirstCommentDate,
        p.Score AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.ClosedDate,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScoreByOwner,
        p.AcceptedAnswerId,
        COALESCE(p.AnswerCount, 0) AS DirectAnswerCount
    FROM Posts AS p
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.LastEditDate, p.ClosedDate, p.AcceptedAnswerId, p.AnswerCount
),
UserBadgeSummary AS (
    -- Summarizes the number of Gold, Silver, and Bronze badges for each user, and unique badge types.
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadgeTypes
    FROM Badges AS b
    GROUP BY b.UserId
),
PostHistoryStatusAggregate AS (
    -- Identifies key historical events for posts, such as closure, reopening, or migration.
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed, -- Post Closed
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened, -- Post Reopened
        MAX(CASE WHEN ph.PostHistoryTypeId = 19 THEN 1 ELSE 0 END) AS WasProtected, -- Question Protected
        MAX(CASE WHEN ph.PostHistoryTypeId = 35 THEN 1 ELSE 0 END) AS WasMigratedAway, -- Post Migrated Away
        MAX(CASE WHEN ph.PostHistoryTypeId = 8 THEN 1 ELSE 0 END) AS HasRollbackBodyHistory -- Rollback Body
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (10, 11, 19, 35, 8)
    GROUP BY ph.PostId
)
SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Unknown User') AS UserDisplayName,
    u.Reputation,
    ur.AnnualRepRank,
    ur.ReputationDecile,
    ur.AvgReputationInLocation,
    EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (60 * 60 * 24 * 365.25) AS UserTenureYears, -- User's age in years
    COALESCE(ubs.GoldBadges, 0) AS TotalGoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS TotalSilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS TotalBronzeBadges,
    ubs.UniqueBadgeTypes,
    SUM(CASE WHEN pcva_q.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsPosted,
    SUM(CASE WHEN pcva_a.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
    SUM(COALESCE(pcva_q.CommentCount, 0) + COALESCE(pcva_a.CommentCount, 0)) AS TotalCommentsOnUserPosts,
    SUM(COALESCE(pcva_q.UpvoteCount, 0) + COALESCE(pcva_a.UpvoteCount, 0)) AS TotalUpvotesReceived,
    SUM(COALESCE(pcva_q.DownvoteCount, 0) + COALESCE(pcva_a.DownvoteCount, 0)) AS TotalDownvotesReceived,
    AVG(pcva_q.PostScore) FILTER (WHERE pcva_q.PostTypeId = 1) AS AvgQuestionScore,
    AVG(pcva_a.PostScore) FILTER (WHERE pcva_a.PostTypeId = 2) AS AvgAnswerScore,
    (SUM(CASE WHEN pcva_q.PostTypeId = 1 THEN pcva_q.PostViewCount ELSE 0 END) * 1.0) / NULLIF(SUM(CASE WHEN pcva_q.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS AvgQuestionViewCount,
    -- Correlated Subquery: Count of answers posted by this user that were accepted by *other* users' questions
    (SELECT COUNT(DISTINCT q_acc.Id)
     FROM Posts AS q_acc
     WHERE q_acc.AcceptedAnswerId IN (SELECT a_inner.Id FROM Posts AS a_inner WHERE a_inner.OwnerUserId = u.Id AND a_inner.PostTypeId = 2)
       AND q_acc.OwnerUserId <> u.Id) AS AnswersAcceptedByOthersCount,
    -- Scalar Subquery: Total score contributed by this user's answers that were accepted by others
    (SELECT COALESCE(SUM(sa.Score), 0)
     FROM Posts AS sq
     JOIN Posts AS sa ON sq.AcceptedAnswerId = sa.Id
     WHERE sa.OwnerUserId = u.Id AND sq.OwnerUserId <> u.Id AND sa.PostTypeId = 2) AS ScoreFromAcceptedAnswers,
    -- Complex string expression and NULL logic for a user's geographical and "About Me" presence
    UPPER(LEFT(COALESCE(u.Location, 'Unspecified'), 3)) || '-' || LPAD(CAST(LENGTH(COALESCE(u.AboutMe, '')) AS TEXT), 4, '0') AS LocationAboutMeHash,
    MAX(CASE WHEN phsa.WasClosed = 1 AND pcva_q.PostId IS NOT NULL THEN 'TRUE' ELSE 'FALSE' END) AS HasClosedQuestions,
    MAX(CASE WHEN phsa.WasMigratedAway = 1 AND pcva_q.PostId IS NOT NULL THEN 'TRUE' ELSE 'FALSE' END) AS HasMigratedQuestions,
    COALESCE(MAX(pcva_q.LastEditDate), MAX(pcva_a.LastEditDate), u.LastAccessDate) AS LastContentOrAccessActivity,
    -- Window function: Rank of the user's answers by upvotes, for their top answer
    MAX(CASE WHEN pcva_a.PostTypeId = 2 THEN RANK() OVER (PARTITION BY u.Id ORDER BY pcva_a.UpvoteCount DESC, pcva_a.PostCreationDate DESC) END) AS TopAnswerUpvoteRank,
    SUM(CASE WHEN pcva_q.PostTypeId = 1 AND pcva_q.PostScore > pcva_q.PreviousPostScoreByOwner THEN 1 ELSE 0 END) AS ImprovedQuestionScoresCount,
    -- Correlated EXISTS subquery: Check if user has ever had a 'rollback body' history entry on any of their questions
    EXISTS (
        SELECT 1
        FROM PostHistory AS ph_rb
        JOIN Posts AS p_rb ON ph_rb.PostId = p_rb.Id
        WHERE p_rb.OwnerUserId = u.Id
          AND p_rb.PostTypeId = 1
          AND ph_rb.PostHistoryTypeId = 8
    ) AS HasQuestionBodyRollbacks,
    -- Correlated scalar subquery: Retrieve the text of the most recent comment made by this user on any post
    (SELECT c_by_user.Text
     FROM Comments AS c_by_user
     WHERE c_by_user.UserId = u.Id
     ORDER BY c_by_user.CreationDate DESC
     LIMIT 1) AS LatestCommentByYou,
    -- Complicated calculation combining post scores and badge counts
    (SUM(COALESCE(pcva_q.PostScore, 0)) + SUM(COALESCE(pcva_a.PostScore, 0))) * (COALESCE(ubs.GoldBadges, 0) + COALESCE(ubs.SilverBadges, 0) * 0.5 + 1) AS WeightedContentScore
FROM
    Users AS u
LEFT JOIN UserReputationRank AS ur ON u.Id = ur.UserId
LEFT JOIN UserBadgeSummary AS ubs ON u.Id = ubs.UserId
LEFT JOIN PostCommentVotesAggregate AS pcva_q ON u.Id = pcva_q.OwnerUserId AND pcva_q.PostTypeId = 1
LEFT JOIN PostCommentVotesAggregate AS pcva_a ON u.Id = pcva_a.OwnerUserId AND pcva_a.PostTypeId = 2
LEFT JOIN PostHistoryStatusAggregate AS phsa ON (pcva_q.PostId = phsa.PostId OR pcva_a.PostId = phsa.PostId) -- Join for either question or answer history
WHERE
    u.Views > (SELECT AVG(Views) FROM Users WHERE AccountId IS NOT NULL AND Views IS NOT NULL) * 0.5 -- Users with above-average views (excluding NULL AccountId and Views)
    AND u.UpVotes > u.DownVotes * 1.5 -- Users with significantly more upvotes than downvotes
    AND EXISTS (
        SELECT 1
        FROM Badges AS b_gold
        WHERE b_gold.UserId = u.Id AND b_gold.Class = 1
    ) -- Only users with at least one Gold badge
    AND (pcva_q.PostId IS NOT NULL OR pcva_a.PostId IS NOT NULL) -- Ensure user has at least one question or answer post (could be `u.Posts > 0` if Posts was pre-aggregated)
    AND COALESCE(u.Location, '') NOT LIKE '%[TEST]%' -- Exclude users from 'test' locations
    AND u.CreationDate > '2010-01-01' -- Exclude very old users for potentially different activity patterns
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.AboutMe, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate,
    ur.AnnualRepRank, ur.ReputationDecile, ur.AvgReputationInLocation,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.UniqueBadgeTypes
HAVING
    SUM(COALESCE(pcva_q.PostScore, 0) + COALESCE(pcva_a.PostScore, 0)) > 100 -- Users with total post score greater than 100
ORDER BY
    WeightedContentScore DESC,
    TotalUpvotesReceived DESC,
    UserTenureYears DESC
LIMIT 1000;
