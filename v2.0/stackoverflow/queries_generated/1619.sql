-- {"query": "1619.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3768} 
WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMade,
        COUNT(DISTINCT v_up.PostId) AS UpVotedPosts,
        COUNT(DISTINCT v_down.PostId) AS DownVotedPosts,
        u.Views AS ProfileViews,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v_up ON u.Id = v_up.UserId AND v_up.VoteTypeId = 2 -- UpMod
    LEFT JOIN Votes v_down ON u.Id = v_down.UserId AND v_down.VoteTypeId = 3 -- DownMod
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
PostDetailsExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount AS PostBaseCommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ph_closed.Comment AS CloseReasonIdComment, -- Schema says this is CloseReasonId if PostHistoryTypeId = 10
        p.ParentId,
        p.AcceptedAnswerId,
        -- Correlated subquery to count edits for the post
        (SELECT COUNT(DISTINCT ph_edit.Id) FROM PostHistory ph_edit WHERE ph_edit.PostId = p.Id AND ph_edit.PostHistoryTypeId IN (4, 5, 6)) AS PostEditCount,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id) AS TotalCommentsOnPost,
        CASE
            WHEN p.Body LIKE '%<pre><code>%' AND p.Body LIKE '%</code></pre>%' THEN TRUE
            ELSE FALSE
        END AS HasCodeBlock,
        CASE
            WHEN p.Tags IS NOT NULL THEN ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1)
            ELSE 0
        END AS TagCount,
        (SELECT MAX(ph_hist.CreationDate) FROM PostHistory ph_hist WHERE ph_hist.PostId = p.Id) AS LastHistoryDate
    FROM Posts p
    LEFT JOIN PostHistory ph_closed ON p.Id = ph_closed.PostId AND ph_closed.PostHistoryTypeId = 10 -- Post Closed
),
AggregatedTagStats AS (
    SELECT
        unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName,
        COUNT(p.Id) AS QuestionsWithTag,
        SUM(p.ViewCount) AS TotalTagViews,
        AVG(p.Score) AS AvgTagQuestionScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
),
PostCommentScores AS (
    SELECT
        c.PostId,
        AVG(c.Score) AS AvgCommentScore,
        SUM(c.Score) AS SumCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
QuestionAnswerMetrics AS (
    SELECT
        q.Id AS QuestionId,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(a.Id) AS ActualAnswerCount,
        MAX(a.CreationDate) AS LatestAnswerDate,
        -- Correlated subquery example: Check if any answer to this question has a very high score
        EXISTS (
            SELECT 1
            FROM Posts high_a
            WHERE high_a.ParentId = q.Id
              AND high_a.PostTypeId = 2
              AND high_a.Score > (SELECT COALESCE(AVG(Score), 0) * 3 FROM Posts WHERE PostTypeId = 2 AND ParentId = q.Id) -- 3x average score for answers to this question
        ) AS HasHighScoringAnswer
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
)
SELECT
    -- User Details
    COALESCE(ues.DisplayName, 'Anonymous User #' || ues.UserId) AS UserIdentifier,
    ues.Reputation,
    ues.UserCreationDate,
    ues.LastAccessDate,
    EXTRACT(DAY FROM (NOW() - ues.UserCreationDate)) AS DaysSinceUserCreation,
    ues.TotalPosts,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.TotalCommentsMade,
    ues.TotalEditsMade,
    ues.GoldBadges,
    ues.SilverBadges,
    ues.BronzeBadges,

    -- Post Details (Questions only for this part)
    pde.PostId AS PostOrAnswerId, -- For UNION ALL consistency
    pde.Title AS PostTitle,
    pde.Score AS PostScore,
    pde.ViewCount AS PostViewCount,
    pde.PostCreationDate AS PostCreationDate,
    pde.TotalCommentsOnPost,
    pde.PostEditCount,
    pde.FavoriteCount AS PostFavoriteCount,
    pde.HasCodeBlock,
    pde.TagCount AS PostTagCount,
    COALESCE(pde.ClosedDate, '1900-01-01 00:00:00'::timestamp) AS ClosedDateIndicator, -- Use a sentinel value for non-closed
    COALESCE(crt.Name, 'Not Closed') AS CloseReasonTypeName,

    -- Answer & Comment Metrics (for questions)
    qam.AvgAnswerScore,
    qam.ActualAnswerCount,
    COALESCE(qam.LatestAnswerDate, '1900-01-01 00:00:00'::timestamp) AS LatestAnswerDate,
    pde.AcceptedAnswerId IS NOT NULL AS HasAcceptedAnswer,
    qam.HasHighScoringAnswer,
    pcs.AvgCommentScore,
    pcs.SumCommentScore,
    COALESCE(pcs.LastCommentDate, '1900-01-01 00:00:00'::timestamp) AS LastCommentDateOnPost,

    -- Tag Performance for Primary Tag (assuming first tag is primary for simplicity)
    ats_primary.QuestionsWithTag AS PrimaryTagQuestions,
    ats_primary.TotalTagViews AS PrimaryTagTotalViews,
    ats_primary.AvgTagQuestionScore AS PrimaryTagAvgScore,

    -- Window Functions & Complex Calculations
    ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY pde.ViewCount DESC, pde.Score DESC) AS UserPostRankByViews,
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM pde.PostCreationDate) ORDER BY pde.Score DESC, pde.ViewCount DESC) AS OverallPostRankByYear,
    AVG(pde.Score) OVER (PARTITION BY ues.UserId) AS AvgUserPostScore,
    (EXTRACT(EPOCH FROM (NOW() - pde.PostCreationDate)) / (60 * 60 * 24)) AS DaysSincePostCreation, -- Days as numeric
    CASE
        WHEN pde.PostEditCount > 5 AND pde.TotalCommentsOnPost > 10 AND pde.Score > 50 THEN 'Highly Engaged & Popular'
        WHEN pde.ClosedDate IS NOT NULL AND pde.HasCodeBlock THEN 'Closed Technical Question'
        WHEN pde.PostTypeId = 1 AND pde.AnswerCount = 0 AND pde.ViewCount > 1000 THEN 'Unanswered Popular Question'
        WHEN pde.FavoriteCount IS NOT NULL AND pde.FavoriteCount > 0 AND pde.Score > 20 THEN 'Favorited & Well-Received'
        ELSE 'General Activity'
    END AS PostCategory,
    NULLIF(pde.ViewCount, 0) / NULLIF(pde.AnswerCount, 0) AS ViewsPerAnswerRatio, -- Division by zero protection

    -- String Expression: Check for specific terms in title
    (pde.Title ILIKE '%performance%' OR pde.Title ILIKE '%optimize%' OR pde.Title ILIKE '%benchmark%') AS IsPerformanceRelated

FROM UserEngagementSummary ues
INNER JOIN PostDetailsExtended pde ON ues.UserId = pde.OwnerUserId
LEFT JOIN CloseReasonTypes crt ON pde.CloseReasonIdComment IS NOT NULL AND pde.CloseReasonIdComment ~ '^[0-9]+$' AND pde.CloseReasonIdComment::smallint = crt.Id
LEFT JOIN QuestionAnswerMetrics qam ON pde.PostId = qam.QuestionId
LEFT JOIN PostCommentScores pcs ON pde.PostId = pcs.PostId
LEFT JOIN LATERAL (
    SELECT (string_to_array(SUBSTRING(pde.Tags, 2, LENGTH(pde.Tags) - 2), '><'))[1] AS first_tag_name
    WHERE pde.Tags IS NOT NULL
) AS primary_tag_unnest ON TRUE
LEFT JOIN AggregatedTagStats ats_primary ON primary_tag_unnest.first_tag_name = ats_primary.TagName
WHERE
    pde.PostTypeId = 1 -- Focus on Questions
    AND ues.Reputation > 10000 -- Filter for influential users
    AND pde.ViewCount > 5000 -- Filter for popular questions
    AND pde.Score > 10 -- Filter for well-received questions
    AND ues.TotalQuestions > 5 -- User has contributed multiple questions
    AND pde.PostCreationDate BETWEEN '2020-01-01' AND '2023-01-01' -- Specific time frame
    AND ues.LastAccessDate >= NOW() - INTERVAL '6 months' -- Recently active users
    AND (pde.FavoriteCount > 5 OR pde.AnswerCount > 2) -- Interesting questions
    AND (NOT pde.HasCodeBlock OR pde.PostEditCount > 2) -- Questions with code blocks that have been edited, or questions without code blocks.

UNION ALL -- Set operator example: Also include top answers from highly reputable users to any question

SELECT
    COALESCE(ues.DisplayName, 'Anonymous User #' || ues.UserId) AS UserIdentifier,
    ues.Reputation,
    ues.UserCreationDate,
    ues.LastAccessDate,
    EXTRACT(DAY FROM (NOW() - ues.UserCreationDate)) AS DaysSinceUserCreation,
    ues.TotalPosts,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.TotalCommentsMade,
    ues.TotalEditsMade,
    ues.GoldBadges,
    ues.SilverBadges,
    ues.BronzeBadges,

    pde.PostId AS PostOrAnswerId,
    pde.Title AS PostTitle, -- NULL for answers
    pde.Score AS PostScore,
    pde.ViewCount AS PostViewCount, -- NULL for answers
    pde.PostCreationDate AS PostCreationDate,
    pde.TotalCommentsOnPost,
    pde.PostEditCount,
    pde.FavoriteCount AS PostFavoriteCount, -- NULL for answers
    pde.HasCodeBlock,
    pde.TagCount AS PostTagCount, -- NULL for answers
    '1900-01-01 00:00:00'::timestamp AS ClosedDateIndicator, -- Not applicable for answers
    'Not Applicable (Answer)' AS CloseReasonTypeName,

    NULL AS AvgAnswerScore, -- Not applicable for answers
    NULL AS ActualAnswerCount, -- Not applicable for answers
    '1900-01-01 00:00:00'::timestamp AS LatestAnswerDate, -- Not applicable for answers
    FALSE AS HasAcceptedAnswer, -- Not applicable for answers directly
    FALSE AS HasHighScoringAnswer, -- Not applicable for answers directly
    pcs.AvgCommentScore,
    pcs.SumCommentScore,
    COALESCE(pcs.LastCommentDate, '1900-01-01 00:00:00'::timestamp) AS LastCommentDateOnPost,

    NULL AS PrimaryTagQuestions, -- Not directly for answers
    NULL AS PrimaryTagTotalViews, -- Not directly for answers
    NULL AS PrimaryTagAvgScore, -- Not directly for answers

    ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY pde.Score DESC, pde.PostCreationDate DESC) AS UserPostRankByViews, -- Rank answers by score
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM pde.PostCreationDate) ORDER BY pde.Score DESC) AS OverallPostRankByYear, -- Rank answers overall
    AVG(pde.Score) OVER (PARTITION BY ues.UserId) AS AvgUserPostScore, -- Avg score for this user's answers
    (EXTRACT(EPOCH FROM (NOW() - pde.PostCreationDate)) / (60 * 60 * 24)) AS DaysSincePostCreation,
    CASE
        WHEN pde.Score > 100 AND pde.HasCodeBlock THEN 'Top Answer with Code'
        WHEN pde.Score > 50 AND pde.TotalCommentsOnPost > 5 THEN 'Highly Discussed Answer'
        ELSE 'General Answer Activity'
    END AS PostCategory,
    NULLIF(pde.Score, 0) / NULLIF(pde.TotalCommentsOnPost, 0) AS ViewsPerAnswerRatio, -- Score per comment ratio for answer
    (pde.Title ILIKE '%solution%' OR pde.Body ILIKE '%example%') AS IsPerformanceRelated -- Body LIKE for TEXT on this branch

FROM UserEngagementSummary ues
INNER JOIN PostDetailsExtended pde ON ues.UserId = pde.OwnerUserId
LEFT JOIN PostCommentScores pcs ON pde.PostId = pcs.PostId
WHERE
    pde.PostTypeId = 2 -- Focus on Answers
    AND ues.Reputation > 50000 -- Even more influential users
    AND pde.Score > 20 -- High-scoring answers
    AND ues.TotalAnswers > 10 -- User has provided many answers
    AND pde.PostCreationDate BETWEEN '2021-01-01' AND '2023-01-01' -- More recent timeframe
    AND pde.ParentId IS NOT NULL -- Must be an answer to a question
    AND EXISTS ( -- Correlated subquery: Ensure parent question is popular and well-received
        SELECT 1 FROM Posts q_parent
        WHERE q_parent.Id = pde.ParentId AND q_parent.ViewCount > 10000 AND q_parent.Score > 50
    );