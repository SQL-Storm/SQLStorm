-- {"query": "1509.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2984} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(p.Score) AS TotalPostScore,
        SUM(c.Score) AS TotalCommentScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        COALESCE(AVG(c.Score), 0) AS AvgCommentScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity,
        -- Window function: Rank users by reputation within their creation year
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC, u.Id) AS RankByReputationInYear
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
    HAVING COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) > 5 -- Only consider users with at least some activity
),
QuestionDetailsExtended AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Tags,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        -- String expression: Extract primary tag (first tag)
        TRIM(SUBSTRING(q.Tags FROM 2 FOR (POSITION('><' IN q.Tags) - 2))) AS PrimaryTag,
        -- Correlated subquery: Check if question was closed and later reopened within a specific timeframe
        EXISTS (
            SELECT 1
            FROM PostHistory ph_close
            WHERE ph_close.PostId = q.Id
              AND ph_close.PostHistoryTypeId = 10 -- Post Closed
              AND EXISTS (
                  SELECT 1
                  FROM PostHistory ph_reopen
                  WHERE ph_reopen.PostId = q.Id
                    AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
                    AND ph_reopen.CreationDate > ph_close.CreationDate
                    AND ph_reopen.CreationDate <= ph_close.CreationDate + INTERVAL '30 days' -- Reopened within 30 days
              )
        ) AS WasClosedThenReopened,
        -- Complicated calculation: Question age in days
        EXTRACT(DAY FROM (CURRENT_TIMESTAMP - q.CreationDate)) AS QuestionAgeDays,
        -- Window function: Average score of all answers for this question
        COALESCE(AVG(ans.Score) OVER (PARTITION BY q.Id), 0) AS AvgAnswerScoreForQuestion
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id AND a.PostTypeId = 2
    LEFT JOIN Posts ans ON q.Id = ans.ParentId AND ans.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 year' -- Focus on recent questions
      AND q.ViewCount > 100
),
PostCommentInteraction AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        c.Id AS CommentId,
        c.CreationDate AS CommentCreationDate,
        c.Score AS CommentScore,
        c.Text AS CommentText,
        -- String expression and NULL logic: Categorize comments based on keywords
        CASE
            WHEN LOWER(c.Text) LIKE '%thank%' OR LOWER(c.Text) LIKE '%great%' THEN 'Positive'
            WHEN LOWER(c.Text) LIKE '%bug%' OR LOWER(c.Text) LIKE '%error%' THEN 'Problem'
            WHEN LOWER(c.Text) IS NULL OR LENGTH(TRIM(c.Text)) = 0 THEN 'Empty'
            ELSE 'Neutral'
        END AS CommentSentiment,
        -- Window function: Rank comments by score within each post to get the "top" comment
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY c.Score DESC, c.CreationDate DESC) AS CommentRankInPost
    FROM Posts p
    JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
      AND c.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
      AND c.UserId IS NOT NULL -- Exclude anonymous comments
),
HighlyVotedAcceptedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        -- Correlated subquery: Check if the answer's owner also has another highly-rated linked post
        EXISTS (
            SELECT 1
            FROM PostLinks pl
            JOIN Posts related_p ON pl.RelatedPostId = related_p.Id
            WHERE pl.PostId = a.Id
              AND pl.LinkTypeId = 1 -- Linked post
              AND related_p.OwnerUserId = a.OwnerUserId
              AND related_p.Score > 50
        ) AS HasHighScoreSelfLink
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.Score >= 100
      AND a.ParentId IS NOT NULL -- Ensure it's an answer to a question
)
-- Main Query: Combine and analyze user activity, question details, comment sentiment, and answer performance
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.UserViews,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalComments,
    uas.TotalBadges,
    qde.QuestionId,
    qde.Title AS QuestionTitle,
    qde.PrimaryTag,
    qde.QuestionScore,
    qde.ViewCount,
    qde.QuestionAgeDays,
    qde.AcceptedAnswerScore,
    qde.WasClosedThenReopened,
    qde.AvgAnswerScoreForQuestion,
    pci.CommentSentiment AS TopCommentSentiment,
    pci.CommentText AS TopCommentText,
    hvaa.AnswerId AS HighScoreAnswerId,
    hvaa.AnswerScore AS HighScoreAnswerScore,
    hvaa.HasHighScoreSelfLink,
    -- Complicated calculation: Ratio of accepted answers to total questions, handling division by zero with NULLIF
    CAST(COALESCE(SUM(CASE WHEN qde.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END), 0) AS DECIMAL) / NULLIF(uas.TotalQuestions, 0) AS AcceptedAnswerRatio,
    -- NULL logic and complex expressions
    COALESCE(qde.QuestionScore, 0) + COALESCE(qde.AcceptedAnswerScore, 0) * 1.5 AS CombinedQuestionValue,
    uas.LastAccessDate - uas.UserCreationDate AS UserTenure,
    CASE
        WHEN uas.Reputation > 10000 AND uas.TotalQuestions > 100 AND uas.TotalAnswers > 50 THEN 'Guru Contributor'
        WHEN uas.Reputation > 1000 AND uas.TotalPosts > 50 THEN 'Active Contributor'
        WHEN uas.Reputation > 100 AND uas.TotalPosts > 10 THEN 'Rookie Contributor'
        ELSE 'Casual User'
    END AS UserContributionLevel
FROM UserActivitySummary uas
LEFT JOIN QuestionDetailsExtended qde ON uas.UserId = qde.OwnerUserId
LEFT JOIN PostCommentInteraction pci ON qde.QuestionId = pci.PostId AND pci.CommentRankInPost = 1 -- Get the highest-scoring comment for each question
LEFT JOIN HighlyVotedAcceptedAnswers hvaa ON uas.UserId = hvaa.OwnerUserId AND qde.AcceptedAnswerId = hvaa.AnswerId
WHERE uas.Reputation > 500
  AND uas.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '6 months'
  AND (
        qde.QuestionId IS NOT NULL
        OR pci.CommentId IS NOT NULL
        OR hvaa.AnswerId IS NOT NULL
      ) -- User must have some relevant post/comment/answer activity
  AND (
        qde.PrimaryTag LIKE 'sql%' OR qde.PrimaryTag LIKE 'database%' OR qde.PrimaryTag IS NULL -- Example tag filtering
      )
  AND (
        pci.CommentSentiment IN ('Positive', 'Problem') OR pci.CommentSentiment IS NULL
      )
  AND (
        hvaa.AnswerScore > uas.AvgPostScore * 2 OR hvaa.AnswerScore IS NULL
      )
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.LastAccessDate, uas.UserViews,
    uas.TotalPosts, uas.TotalQuestions, uas.TotalAnswers, uas.TotalComments, uas.TotalBadges,
    qde.QuestionId, qde.Title, qde.PrimaryTag, qde.QuestionScore, qde.ViewCount, qde.QuestionAgeDays,
    qde.AcceptedAnswerScore, qde.WasClosedThenReopened, qde.AvgAnswerScoreForQuestion,
    pci.CommentSentiment, pci.CommentText, hvaa.AnswerId, hvaa.AnswerScore, hvaa.HasHighScoreSelfLink
HAVING COALESCE(uas.AvgPostScore, 0) > 5
   AND (uas.TotalQuestions > 0 OR uas.TotalAnswers > 0 OR uas.TotalComments > 0)
UNION ALL
-- Set operator: Find users who primarily engage through comments and have a significant number of positive comments, but few or no posts
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.UserViews,
    0 AS TotalPosts, -- For this union branch, posts are intentionally set to 0 to identify comment-focused users
    0 AS TotalQuestions,
    0 AS TotalAnswers,
    uas.TotalComments,
    uas.TotalBadges,
    NULL AS QuestionId,
    NULL AS QuestionTitle,
    NULL AS PrimaryTag,
    NULL AS QuestionScore,
    NULL AS ViewCount,
    NULL AS QuestionAgeDays,
    NULL AS AcceptedAnswerScore,
    NULL AS WasClosedThenReopened,
    NULL AS AvgAnswerScoreForQuestion,
    pci_top_commenter.CommentSentiment AS TopCommentSentiment,
    pci_top_commenter.CommentText AS TopCommentText,
    NULL AS HighScoreAnswerId,
    NULL AS HighScoreAnswerScore,
    NULL AS HasHighScoreSelfLink,
    0 AS AcceptedAnswerRatio,
    NULL AS CombinedQuestionValue,
    uas.LastAccessDate - uas.UserCreationDate AS UserTenure,
    'Comment-Only Enthusiast' AS UserContributionLevel
FROM UserActivitySummary uas
JOIN (
    SELECT
        PostId,
        UserId,
        CommentSentiment,
        CommentText,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Score DESC, CreationDate DESC) as rn
    FROM PostCommentInteraction
    WHERE CommentSentiment = 'Positive' -- Focus on positive comments for this branch
) pci_top_commenter ON uas.UserId = pci_top_commenter.UserId AND pci_top_commenter.rn = 1
WHERE uas.TotalQuestions = 0
  AND uas.TotalAnswers = 0
  AND uas.TotalPosts = 0
  AND uas.TotalComments > 100 -- Users with a high number of comments
  AND uas.Reputation > 100
  AND uas.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
  AND pci_top_commenter.CommentSentiment = 'Positive'
ORDER BY Reputation DESC, UserTenure DESC;
