-- {"query": "1779.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2338} 

WITH UserGoldenBadges AS (
    -- CTE to identify users who possess at least one Gold badge (Class = 1)
    SELECT DISTINCT UserId
    FROM Badges
    WHERE Class = 1
),
UserPostEditSummary AS (
    -- CTE to summarize users' self-edits on their own posts within the last 180 days.
    -- Filters for specific PostHistoryTypes (4: Edit Title, 5: Edit Body, 6: Edit Tags)
    -- and ensures the user editing is the original owner of the post.
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS SelfEditedPostsCount_180Days
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id AND ph.UserId = p.OwnerUserId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '180 days'
    GROUP BY ph.UserId
    HAVING COUNT(DISTINCT ph.PostId) >= 3 -- Only consider users with at least 3 distinct self-edited posts
),
UserAnswerStats AS (
    -- CTE to gather statistics for user-owned answers, including total count, average score,
    -- and count of answers accepted by the question's originator (VoteTypeId = 1).
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalAnswers,
        COALESCE(AVG(p.Score), 0) AS AverageAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 1
    WHERE p.PostTypeId = 2 -- Answer
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) >= 10 AND COALESCE(AVG(p.Score), 0) >= 5 -- Filters for users with substantial and well-received answer contributions
),
UserQuestionStats AS (
    -- CTE to gather statistics for user-owned questions, including total count and average score.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalQuestions,
        COALESCE(AVG(p.Score), 0) AS AverageQuestionScore
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Question
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) >= 5 AND COALESCE(AVG(p.Score), 0) >= 10 -- Filters for users with a significant number of well-received questions
),
UserCommentActivity AS (
    -- CTE to count the number of distinct posts a user has commented on.
    SELECT
        c.UserId,
        COUNT(DISTINCT c.PostId) AS DistinctCommentedPosts
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
    HAVING COUNT(DISTINCT c.PostId) >= 10 -- Filters for users actively engaging in comments
),
QuestionAnswerAverageScore AS (
    -- CTE to pre-calculate the average score of all answers for each question.
    SELECT
        q.Id AS QuestionId,
        COALESCE(AVG(a.Score), 0.0) AS AvgAnswerScore
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2
    GROUP BY q.Id
),
QuestionUpVoterCounts AS (
    -- CTE to count unique users who have cast an 'UpMod' vote (VoteTypeId = 2) on
    -- any of the answers belonging to a specific question.
    SELECT
        q.Id AS QuestionId,
        COUNT(DISTINCT v.UserId) AS UniqueUpVotersOnAnswers
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    JOIN Votes v ON a.Id = v.PostId
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2 AND v.VoteTypeId = 2
    GROUP BY q.Id
),
UsersWithProblematicPosts AS (
    -- CTE to identify users who have had any of their posts closed with the reason 'Not a real question' (CloseReasonTypes Id = 4).
    -- Assumes PostHistory.Comment stores the CloseReasonId as text for PostHistoryTypeId 10.
    SELECT DISTINCT ph.UserId
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.Comment = crt.Id::text
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND crt.Id = 4 -- 'Not a real question'
      AND ph.UserId IS NOT NULL
),
UserEligibilityBase AS (
    -- Consolidate initial eligibility criteria for "Power Users" by joining all preceding activity-based CTEs.
    -- Applies general user filters: CreationDate, LastAccessDate, Location (excluding 'anonymous'), and non-NULL WebsiteUrl.
    SELECT u.Id AS UserId
    FROM Users u
    JOIN UserGoldenBadges ugb ON u.Id = ugb.UserId
    JOIN UserPostEditSummary upes ON u.Id = upes.UserId
    JOIN UserAnswerStats uas ON u.Id = uas.UserId
    JOIN UserQuestionStats uqs ON u.Id = uqs.UserId
    JOIN UserCommentActivity uca ON u.Id = uca.UserId
    WHERE u.CreationDate < '2020-01-01'
      AND u.LastAccessDate >= '2023-01-01'
      AND (u.Location IS NULL OR LOWER(u.Location) NOT LIKE '%anonymous%')
      AND u.WebsiteUrl IS NOT NULL
),
UserEligibility AS (
    -- Applies a set operator (EXCEPT) to remove users identified as having "problematic posts"
    -- from the initially eligible "Power Users" list.
    SELECT UserId FROM UserEligibilityBase
    EXCEPT
    SELECT UserId FROM UsersWithProblematicPosts
),
UserQuestionsWithRank AS (
    -- Ranks each user's questions based on their LastActivityDate in descending order.
    -- Includes a tie-breaker by PostId for deterministic ranking.
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title AS QuestionTitle,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.CreationDate AS QuestionCreationDate,
        p.LastActivityDate AS QuestionLastActivityDate,
        p.CommentCount AS QuestionCommentCount,
        p.FavoriteCount AS QuestionFavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC, p.Id DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
)
-- Main query: Retrieves detailed information for "Power Users" and their top 3 most active questions.
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    -- Classifies users into Reputation Tiers based on their Reputation score
    CASE
        WHEN u.Reputation >= 100000 THEN 'Legendary'
        WHEN u.Reputation >= 50000 THEN 'Epic'
        WHEN u.Reputation >= 20000 THEN 'Master'
        WHEN u.Reputation >= 5000 THEN 'Expert'
        WHEN u.Reputation >= 1000 THEN 'Advanced'
        ELSE 'Contributor'
    END AS ReputationTier,
    COALESCE(uas.AverageAnswerScore, 0.0) AS UserOverallAvgAnswerScore,
    COALESCE(uas.AcceptedAnswersCount, 0) AS UserAcceptedAnswerVotes,
    -- Extracts and cleanses a snippet from the user's AboutMe text, replacing common HTML tags
    -- and truncating to 100 characters, defaulting to '[No Bio]' if NULL.
    SUBSTRING(
        COALESCE(
            REPLACE(REPLACE(REPLACE(u.AboutMe, '<p>', ''), '</p>', ' '), '<a>', ''),
            '[No Bio]'
        ) FOR 100
    ) AS AboutMeSnippet,
    -- Details for the user's top questions
    uqr.QuestionId,
    uqr.QuestionTitle,
    uqr.QuestionScore,
    uqr.QuestionViewCount,
    uqr.QuestionCommentCount,
    qaas.AvgAnswerScore AS QuestionAvgAnswerScore,
    COALESCE(quvc.UniqueUpVotersOnAnswers, 0) AS QuestionUniqueUpVotersOnAnswers,
    -- Calculates a 'Question Engagement Index' based on views, score, comments, and favorites,
    -- normalized by the question's age in days. Handles potential division by zero.
    CAST(
        (uqr.QuestionViewCount + (uqr.QuestionScore * 2) + uqr.QuestionCommentCount + (COALESCE(uqr.QuestionFavoriteCount, 0) * 3.0))
        / NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - uqr.QuestionCreationDate)) / (60 * 60 * 24.0), 0)
    AS NUMERIC(10, 4)) AS QuestionEngagementIndex,
    uqr.QuestionLastActivityDate,
    uqr.rn AS QuestionActivityRank
FROM Users u
JOIN UserEligibility ue ON u.Id = ue.UserId -- Filters for eligible "Power Users"
LEFT JOIN UserAnswerStats uas ON u.Id = uas.UserId
JOIN UserQuestionsWithRank uqr ON u.Id = uqr.OwnerUserId -- Joins with ranked questions owned by the user
LEFT JOIN QuestionAnswerAverageScore qaas ON uqr.QuestionId = qaas.QuestionId
LEFT JOIN QuestionUpVoterCounts quvc ON uqr.QuestionId = quvc.QuestionId
WHERE uqr.rn <= 3 -- Limits results to the top 3 most active questions per user
ORDER BY u.Id, uqr.rn;
