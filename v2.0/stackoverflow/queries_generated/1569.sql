-- {"query": "1569.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3545} 

WITH UserEngagement AS (
    -- CTE 1: Summarizes user's overall activity, reputation tier, and ranks them by reputation within their creation year.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity,
        -- Calculate average post score for the user, handling cases with no posts.
        COALESCE(AVG(p.Score) FILTER (WHERE p.OwnerUserId = u.Id), 0) AS AvgPostScore,
        -- Determine a reputation tier using a CASE statement and NULL logic for AccountId.
        CASE
            WHEN u.Reputation >= 20000 AND u.AccountId IS NOT NULL THEN 'Elite User'
            WHEN u.Reputation >= 5000 AND u.Views > 5000 THEN 'Experienced Contributor'
            WHEN u.Reputation >= 1000 AND u.DisplayName IS NOT NULL THEN 'Active Member'
            WHEN u.Reputation > 0 THEN 'Novice'
            ELSE 'Dormant' -- For users with 0 reputation.
        END AS ReputationTier,
        -- Rank users by reputation within their creation year using a window function.
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC, u.Id) AS RankInCreationYear
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes, u.AccountId
    HAVING COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) > 0 -- Only include users with some form of activity.
),
QuestionMetrics AS (
    -- CTE 2: Provides detailed metrics for Questions (PostTypeId = 1), including tag analysis and closure reasons.
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.OwnerUserId,
        q.Tags,
        -- Calculate the 'Answer Ratio', using NULLIF to prevent division by zero.
        CAST(q.AnswerCount AS NUMERIC) / NULLIF(q.ViewCount, 0) AS AnswerViewRatio,
        -- Extract the first tag from the Tags string using string functions.
        TRIM(SUBSTRING(q.Tags, POSITION('<' IN q.Tags) + 1, POSITION('>' IN q.Tags) - POSITION('<' IN q.Tags) - 1)) AS PrimaryTag,
        -- Correlated subquery: Count distinct closure reasons for each question.
        (
            SELECT COUNT(DISTINCT ph.Comment)
            FROM PostHistory ph
            WHERE ph.PostId = q.Id
              AND ph.PostHistoryTypeId = 10 -- Post Closed event.
              AND ph.Comment IS NOT NULL
        ) AS DistinctCloseReasons,
        -- Determine if the question has a 'hot' tag using LIKE operator.
        CASE
            WHEN q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<database>%' OR q.Tags LIKE '%<performance>%' THEN TRUE
            ELSE FALSE
        END AS HasHotTag,
        -- Calculate the time difference in hours between last activity and creation.
        EXTRACT(EPOCH FROM (q.LastActivityDate - q.CreationDate)) / 3600 AS HoursSinceCreationToLastActivity,
        -- Window function: Rank questions by score within their primary tag.
        RANK() OVER (PARTITION BY TRIM(SUBSTRING(q.Tags, POSITION('<' IN q.Tags) + 1, POSITION('>' IN q.Tags) - POSITION('<' IN q.Tags) - 1)) ORDER BY q.Score DESC) AS TagScoreRank
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= (NOW() - INTERVAL '5 year') -- Filter for recent questions.
      AND q.ViewCount > 100 -- Minimum view count for relevance.
),
AnswerAggregates AS (
    -- CTE 3: Aggregates data for Answers related to a question, including accepted answer score.
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate,
        -- Identify the accepted answer's score if it exists, using a CASE statement.
        MAX(CASE WHEN q.AcceptedAnswerId = a.Id THEN a.Score ELSE NULL END) AS AcceptedAnswerScore,
        -- Window function: Find the highest scored answer for each question.
        MAX(a.Score) OVER (PARTITION BY a.ParentId) AS MaxAnswerScoreForQuestion
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id -- Join with Questions to get accepted answer information.
    WHERE a.PostTypeId = 2 -- Only answers.
    GROUP BY a.ParentId, q.AcceptedAnswerId
),
PostLinkAnalysis AS (
    -- CTE 4: Analyzes linked and duplicate posts.
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId ELSE NULL END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS DuplicatePostsCount,
        -- Correlated subquery: Checks if any directly linked posts are closed.
        EXISTS (
            SELECT 1 FROM Posts rp
            WHERE rp.Id IN (
                SELECT pl_inner.RelatedPostId
                FROM PostLinks pl_inner
                WHERE pl_inner.PostId = pl.PostId AND pl_inner.LinkTypeId = 1
            ) AND rp.ClosedDate IS NOT NULL
        ) AS HasClosedLinkedPost
    FROM PostLinks pl
    GROUP BY pl.PostId
),
RecentModeratorActions AS (
    -- CTE 5: Captures recent moderator actions on posts, using LAG for sequential action analysis.
    SELECT
        ph.PostId,
        ph.CreationDate AS ActionDate,
        ph.PostHistoryTypeId,
        ph.UserId AS ModeratorId,
        LAG(ph.PostHistoryTypeId, 1, 0) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousActionTypeId,
        LAG(ph.UserId, 1, -1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousActionUserId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn -- To get the most recent action per post.
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Close, Reopen, Delete, Undelete, Lock, Unlock, Protect, Unprotect.
      AND ph.CreationDate >= (NOW() - INTERVAL '1 year')
),
TopActiveTags AS (
    -- CTE 6: Identifies the top 100 most active tags based on recent questions and their scores, including cumulative count.
    SELECT
        t.TagName,
        COUNT(DISTINCT q.Id) AS QuestionCount,
        SUM(q.Score) AS TotalScore,
        -- Window function: Calculates a cumulative question count ordered by total score.
        SUM(COUNT(DISTINCT q.Id)) OVER (ORDER BY SUM(q.Score) DESC) AS CumulativeQuestionCount
    FROM Tags t
    JOIN Posts q ON q.Tags LIKE '%<' || t.TagName || '>%' -- Uses dynamic LIKE for tag matching.
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= (NOW() - INTERVAL '2 year')
    GROUP BY t.TagName
    ORDER BY TotalScore DESC
    LIMIT 100
)
-- Main Query: Combines all CTEs and performs final aggregations and selections for popular questions.
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.ReputationTier,
    ue.AvgPostScore,
    qm.QuestionTitle,
    qm.QuestionCreationDate,
    qm.QuestionScore,
    qm.ViewCount,
    qm.PrimaryTag,
    qm.HasHotTag,
    qm.TagScoreRank,
    aa.TotalAnswers,
    aa.TotalAnswerScore,
    aa.AcceptedAnswerScore,
    pla.LinkedPostsCount,
    pla.DuplicatePostsCount,
    pla.HasClosedLinkedPost,
    rma.ActionDate AS LastModActionDate,
    rma.PostHistoryTypeId AS LastModActionType,
    rma.PreviousActionTypeId AS PrevModActionType,
    t.TagName AS TopTag,
    t.QuestionCount AS TopTagQuestionCount,
    t.TotalScore AS TopTagTotalScore,
    -- Complicated calculation: A weighted score for questions, favoring score, views, answer count, and recent activity.
    (qm.QuestionScore * 0.5) + (LOG(GREATEST(qm.ViewCount, 1)) * 0.2) + (COALESCE(qm.AnswerCount, 0) * 0.1) +
    (
        CASE
            WHEN qm.HoursSinceCreationToLastActivity IS NOT NULL
            THEN 100.0 / (qm.HoursSinceCreationToLastActivity + 1)
            ELSE 0
        END
    ) AS WeightedQuestionScore,
    -- String manipulation and NULL handling for a User Identifier Code.
    COALESCE(UPPER(SUBSTRING(ue.DisplayName, 1, 3)) || LPAD(CAST(ue.UserId AS TEXT), 7, '0'), 'UNKNOWN_USER') AS UserIdentifierCode,
    -- Correlated subquery: Retrieves the text of the latest comment made by the post owner on their own post.
    (
        SELECT c_inner.Text
        FROM Comments c_inner
        WHERE c_inner.PostId = qm.QuestionId
          AND c_inner.UserId = qm.OwnerUserId
        ORDER BY c_inner.CreationDate DESC
        LIMIT 1
    ) AS LatestOwnerComment,
    -- Correlated subquery: Checks if the user has any gold badges.
    EXISTS (
        SELECT 1 FROM Badges b_inner
        WHERE b_inner.UserId = ue.UserId AND b_inner.Class = 1
    ) AS HasGoldBadge
FROM QuestionMetrics qm
JOIN UserEngagement ue ON qm.OwnerUserId = ue.UserId
LEFT JOIN AnswerAggregates aa ON qm.QuestionId = aa.QuestionId
LEFT JOIN PostLinkAnalysis pla ON qm.QuestionId = pla.PostId
LEFT JOIN RecentModeratorActions rma ON qm.QuestionId = rma.PostId AND rma.rn = 1 -- Join for the most recent moderator action.
LEFT JOIN TopActiveTags t ON qm.PrimaryTag = t.TagName
WHERE qm.QuestionScore >= 5
  AND (qm.AnswerCount > 0 OR qm.FavoriteCount IS NOT NULL)
  AND ue.TotalPosts >= 5 -- Filter for users with sufficient activity.
  AND NOT EXISTS (
      -- Exclude questions that have been deleted or locked, using NOT EXISTS.
      SELECT 1 FROM PostHistory ph_exclude
      WHERE ph_exclude.PostId = qm.QuestionId
        AND ph_exclude.PostHistoryTypeId IN (12, 14) -- Post Deleted or Post Locked.
  )

UNION ALL -- Set operator: Combines results with high-scoring answers.

-- Second part of the UNION ALL: Focuses on high-scoring answers from reputable users.
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.ReputationTier,
    ue.AvgPostScore,
    SUBSTRING(p_ans.Body, 1, 200) AS QuestionTitle, -- Using answer body as 'title' for column consistency.
    p_ans.CreationDate AS QuestionCreationDate,
    p_ans.Score AS QuestionScore,
    NULL AS ViewCount, -- Answers do not have direct view counts.
    NULL AS PrimaryTag,
    FALSE AS HasHotTag,
    NULL AS TagScoreRank,
    NULL AS TotalAnswers,
    p_ans.Score AS TotalAnswerScore, -- Score of the answer itself.
    NULL AS AcceptedAnswerScore,
    NULL AS LinkedPostsCount,
    NULL AS DuplicatePostsCount,
    FALSE AS HasClosedLinkedPost,
    rma.ActionDate AS LastModActionDate,
    rma.PostHistoryTypeId AS LastModActionType,
    rma.PreviousActionTypeId AS PrevModActionType,
    NULL AS TopTag,
    NULL AS TopTagQuestionCount,
    NULL AS TopTagTotalScore,
    -- Weighted score for answers, favoring high score and recent activity.
    (p_ans.Score * 0.7) + (
        CASE
            WHEN EXTRACT(EPOCH FROM (NOW() - p_ans.CreationDate)) / 3600 IS NOT NULL
            THEN 50.0 / (EXTRACT(EPOCH FROM (NOW() - p_ans.CreationDate)) / 3600 + 1)
            ELSE 0
        END
    ) AS WeightedQuestionScore,
    COALESCE(UPPER(SUBSTRING(ue.DisplayName, 1, 3)) || LPAD(CAST(ue.UserId AS TEXT), 7, '0'), 'UNKNOWN_USER') AS UserIdentifierCode,
    -- Correlated subquery for the latest comment by the answer owner on their answer.
    (
        SELECT c_inner.Text
        FROM Comments c_inner
        WHERE c_inner.PostId = p_ans.Id
          AND c_inner.UserId = p_ans.OwnerUserId
        ORDER BY c_inner.CreationDate DESC
        LIMIT 1
    ) AS LatestOwnerComment,
    EXISTS (
        SELECT 1 FROM Badges b_inner
        WHERE b_inner.UserId = ue.UserId AND b_inner.Class = 1
    ) AS HasGoldBadge
FROM Posts p_ans
JOIN UserEngagement ue ON p_ans.OwnerUserId = ue.UserId
LEFT JOIN RecentModeratorActions rma ON p_ans.Id = rma.PostId AND rma.rn = 1
WHERE p_ans.PostTypeId = 2 -- Only answers.
  AND p_ans.Score >= 10 -- Filter for high-scoring answers.
  AND p_ans.CreationDate >= (NOW() - INTERVAL '3 year')
  AND ue.ReputationTier IN ('Elite User', 'Experienced Contributor') -- Only from more reputable users.
ORDER BY WeightedQuestionScore DESC, QuestionCreationDate DESC
LIMIT 1000; -- Limits the final result set for performance benchmarking.
