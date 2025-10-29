-- {"query": "1851.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3591} 
WITH PostEditActivity AS (
    -- Calculate edit counts and last edit timestamps for posts
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        -- Select a User ID associated with a recent edit, for potential LastEditor lookup
        MAX(ph.UserId) AS LastEditorUserId_Agg,
        MIN(ph.CreationDate) AS InitialCreationDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (
        1, -- Initial Title
        2, -- Initial Body
        3, -- Initial Tags
        4, -- Edit Title
        5, -- Edit Body
        6, -- Edit Tags
        7, 8, 9, -- Rollback operations
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66 -- Various other post lifecycle events
    )
    GROUP BY ph.PostId
),
PostVoteSummary AS (
    -- Summarize upvotes, downvotes, and favorite counts for posts
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount, -- UpMod
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount, -- DownMod
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount_Actual, -- Favorite (bookmark)
        COUNT(v.Id) AS TotalVoteEvents
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5, 6, 7, 10, 11, 12) -- Relevant vote types for score/status
    GROUP BY v.PostId
),
UserEngagementMetrics AS (
    -- Aggregate user-specific engagement statistics
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
QuestionContext AS (
    -- Extract and enrich question-specific data
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.OwnerUserId AS QuestionOwnerUserId,
        p.OwnerDisplayName AS QuestionOwnerDisplayNameRaw, -- Raw display name from Posts
        p.Tags AS QuestionTags,
        p.AnswerCount AS QuestionAnswerCount,
        p.CommentCount AS QuestionCommentCount,
        p.FavoriteCount AS QuestionFavoriteCount,
        ph.EditCount,
        ph.LastEditDate,
        ph.LastEditorUserId_Agg AS QuestionLastEditorUserId,
        p.LastEditorDisplayName AS QuestionLastEditorDisplayNameRaw, -- Raw last editor display name
        pvs.UpvoteCount AS QuestionUpvoteCount,
        pvs.DownvoteCount AS QuestionDownvoteCount,
        pvs.FavoriteCount_Actual AS QuestionFavoriteCountActual,
        pvs.TotalVoteEvents AS QuestionTotalVoteEvents,
        -- Calculate Upvote Ratio, handling division by zero for no votes
        (CAST(pvs.UpvoteCount AS NUMERIC) / NULLIF(COALESCE(pvs.DownvoteCount,0) + COALESCE(pvs.UpvoteCount,0), 0)) AS QuestionUpvoteRatio,
        COALESCE(p.ClosedDate IS NOT NULL, FALSE) AS IsClosed,
        COALESCE(p.CommunityOwnedDate IS NOT NULL, FALSE) AS IsCommunityWiki
    FROM Posts p
    LEFT JOIN PostEditActivity ph ON p.Id = ph.PostId
    LEFT JOIN PostVoteSummary pvs ON p.Id = pvs.PostId
    WHERE p.PostTypeId = 1 -- Filter for questions only
),
AnswerContext AS (
    -- Extract and enrich answer-specific data, linked to questions
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.CreationDate AS AnswerCreationDate,
        p.Score AS AnswerScore,
        p.OwnerUserId AS AnswerOwnerUserId,
        p.OwnerDisplayName AS AnswerOwnerDisplayNameRaw, -- Raw display name from Posts
        ph.EditCount AS AnswerEditCount,
        ph.LastEditDate AS AnswerLastEditDate,
        ph.LastEditorUserId_Agg AS AnswerLastEditorUserId,
        p.LastEditorDisplayName AS AnswerLastEditorDisplayNameRaw, -- Raw last editor display name
        pvs.UpvoteCount AS AnswerUpvoteCount,
        pvs.DownvoteCount AS AnswerDownvoteCount,
        (CAST(pvs.UpvoteCount AS NUMERIC) / NULLIF(COALESCE(pvs.DownvoteCount,0) + COALESCE(pvs.UpvoteCount,0), 0)) AS AnswerUpvoteRatio,
        -- Window functions to rank answers within their respective questions
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate ASC) AS AnswerSequenceNum,
        RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerScoreRank
    FROM Posts p
    LEFT JOIN PostEditActivity ph ON p.Id = ph.PostId
    LEFT JOIN PostVoteSummary pvs ON p.Id = pvs.PostId
    WHERE p.PostTypeId = 2 -- Filter for answers only
),
CombinedPostAnalysis AS (
    -- Join questions and answers with user and activity data
    SELECT
        qc.QuestionId,
        qc.QuestionTitle,
        qc.QuestionCreationDate,
        qc.QuestionScore,
        qc.QuestionViewCount,
        -- Use COALESCE for robust display name lookup (Users > Posts.DisplayName > fallback)
        COALESCE(qu.DisplayName, qc.QuestionOwnerDisplayNameRaw, 'Deleted User') AS QuestionOwnerDisplayName,
        qc.QuestionOwnerUserId,
        qc.QuestionTags,
        qc.QuestionAnswerCount,
        qc.QuestionCommentCount,
        qc.QuestionFavoriteCount,
        qc.EditCount AS QuestionEditCount,
        qc.LastEditDate AS QuestionLastEditDate,
        COALESCE(qlu.DisplayName, qc.QuestionLastEditorDisplayNameRaw, 'N/A') AS QuestionLastEditorDisplayName,
        qc.QuestionUpvoteCount,
        qc.QuestionDownvoteCount,
        qc.QuestionUpvoteRatio,
        qc.IsClosed,
        qc.IsCommunityWiki,
        ac.AnswerId,
        ac.AnswerCreationDate,
        ac.AnswerScore,
        COALESCE(au.DisplayName, ac.AnswerOwnerDisplayNameRaw, 'Deleted User') AS AnswerOwnerDisplayName,
        ac.AnswerOwnerUserId,
        ac.AnswerEditCount,
        ac.AnswerLastEditDate,
        ac.AnswerUpvoteCount,
        ac.AnswerDownvoteCount,
        ac.AnswerUpvoteRatio,
        ac.AnswerSequenceNum,
        ac.AnswerScoreRank,
        -- Window functions for broader context
        COUNT(ac.AnswerId) OVER (PARTITION BY qc.QuestionOwnerUserId) AS QuestionsWithAnswersByOwner,
        AVG(ac.AnswerScore) OVER (PARTITION BY qc.QuestionId) AS AvgAnswerScoreForQuestion,
        ROW_NUMBER() OVER (PARTITION BY qc.QuestionOwnerUserId ORDER BY qc.QuestionCreationDate DESC) AS OwnerQuestionSequenceDesc,
        DENSE_RANK() OVER (ORDER BY qc.QuestionScore DESC, qc.QuestionViewCount DESC) AS GlobalQuestionScoreRank
    FROM QuestionContext qc
    LEFT JOIN Users qu ON qc.QuestionOwnerUserId = qu.Id
    LEFT JOIN Users qlu ON qc.QuestionLastEditorUserId = qlu.Id
    LEFT JOIN AnswerContext ac ON qc.QuestionId = ac.QuestionId
    LEFT JOIN Users au ON ac.AnswerOwnerUserId = au.Id
),
FinalAnalysis AS (
    -- Apply final business logic, complex expressions, and subqueries
    SELECT
        cpa.QuestionId,
        cpa.QuestionTitle,
        cpa.QuestionOwnerDisplayName,
        cpa.QuestionOwnerUserId,
        uer.Reputation AS QuestionOwnerReputation,
        uer.TotalPosts AS QuestionOwnerTotalPosts,
        uer.TotalComments AS QuestionOwnerTotalComments,
        uer.GoldBadges AS QuestionOwnerGoldBadges,
        cpa.AnswerId,
        cpa.AnswerOwnerDisplayName,
        cpa.AnswerOwnerUserId,
        auer.Reputation AS AnswerOwnerReputation,
        auer.TotalPosts AS AnswerOwnerTotalPosts,
        auer.TotalComments AS AnswerOwnerTotalComments,
        cpa.QuestionScore,
        cpa.QuestionViewCount,
        cpa.QuestionUpvoteRatio,
        cpa.QuestionEditCount,
        cpa.IsClosed,
        cpa.IsCommunityWiki,
        cpa.AnswerScore,
        cpa.AnswerUpvoteRatio,
        cpa.AnswerSequenceNum,
        cpa.AnswerScoreRank,
        cpa.GlobalQuestionScoreRank,
        cpa.OwnerQuestionSequenceDesc,
        cpa.AvgAnswerScoreForQuestion,
        -- Complicated Predicates/Expressions/Calculations & String Expressions
        CASE
            WHEN cpa.QuestionUpvoteRatio IS NOT NULL AND cpa.QuestionUpvoteRatio < 0.5 AND COALESCE(cpa.QuestionDownvoteCount, 0) > 5 AND COALESCE(cpa.QuestionEditCount, 0) > 3 THEN 'Highly Controversial'
            WHEN cpa.IsClosed AND COALESCE(cpa.QuestionAnswerCount, 0) = 0 THEN 'Closed No Answers'
            WHEN cpa.AnswerScoreRank = 1 AND COALESCE(cpa.AnswerScore, 0) < 0 THEN 'Best Answer Negative Score'
            ELSE 'Standard'
        END AS QuestionIssueCategory,
        NULLIF(LENGTH(TRIM(REPLACE(REPLACE(REPLACE(cpa.QuestionTitle, ' ', ''), '.', ''), ',', ''))), 0) AS TitleAlphaNumericLength,
        REPLACE(SUBSTRING(cpa.QuestionTags, 2, LENGTH(cpa.QuestionTags)-2), '><', ', ') AS FormattedQuestionTags,
        -- Correlated Subquery: Check if question owner has a specific gold badge
        (SELECT COUNT(b.Id)
         FROM Badges b
         WHERE b.UserId = cpa.QuestionOwnerUserId
           AND b.Name = 'Stellar Question' -- Example specific badge
           AND b.Class = 1
        ) > 0 AS HasStellarQuestionBadge,
        -- Another correlated subquery: Count comments on this specific answer by the answer owner
        (SELECT COUNT(co.Id)
         FROM Comments co
         WHERE co.PostId = cpa.AnswerId
           AND co.UserId = cpa.AnswerOwnerUserId
        ) AS AnswerOwnerCommentsOnOwnAnswer,
        -- NULL Logic and complicated expressions
        COALESCE(uer.Reputation, 0) + COALESCE(auer.Reputation, 0) AS CombinedOwnerReputation,
        ABS(COALESCE(cpa.QuestionScore, 0) - COALESCE(cpa.AnswerScore, 0)) AS ScoreDifference,
        CASE
            WHEN cpa.QuestionTags LIKE '%<sql>%' OR cpa.QuestionTags LIKE '%<database>%' THEN 'Database Related'
            WHEN cpa.QuestionTags LIKE '%<javascript>%' OR cpa.QuestionTags LIKE '%<frontend>%' THEN 'Frontend Related'
            WHEN cpa.QuestionTags IS NULL THEN 'Untagged'
            ELSE 'Other Tech'
        END AS TagCategory
    FROM CombinedPostAnalysis cpa
    LEFT JOIN UserEngagementMetrics uer ON cpa.QuestionOwnerUserId = uer.UserId
    LEFT JOIN UserEngagementMetrics auer ON cpa.AnswerOwnerUserId = auer.UserId
    WHERE cpa.QuestionId IS NOT NULL -- Ensure a valid question record
)
-- Use a Set Operator (UNION ALL) to combine two distinct result sets
-- Segment 1: High-impact, well-answered, and edited questions related to databases
SELECT
    fa.QuestionId,
    fa.QuestionTitle,
    fa.QuestionOwnerDisplayName,
    fa.QuestionOwnerReputation,
    fa.QuestionIssueCategory,
    fa.FormattedQuestionTags,
    fa.TitleAlphaNumericLength,
    fa.HasStellarQuestionBadge,
    fa.CombinedOwnerReputation,
    fa.ScoreDifference,
    fa.TagCategory,
    'High Impact Question' AS QuerySegmentType
FROM FinalAnalysis fa
WHERE fa.QuestionScore >= 100
  AND fa.QuestionAnswerCount > 5
  AND COALESCE(fa.QuestionEditCount, 0) > 10
  AND fa.HasStellarQuestionBadge IS TRUE
  AND fa.TagCategory = 'Database Related'
  AND fa.QuestionIssueCategory <> 'Closed No Answers'
  AND fa.AnswerId IS NOT NULL -- Must have an answer to be considered well-answered
  AND fa.AnswerScore IS NOT NULL
  AND fa.AnswerScoreRank <= 3 -- At least one highly-ranked answer exists

UNION ALL

-- Segment 2: Potential problematic questions with low upvote ratio, multiple edits,
-- from less experienced users, and possibly closed/community wiki.
SELECT
    fa.QuestionId,
    fa.QuestionTitle,
    fa.QuestionOwnerDisplayName,
    fa.QuestionOwnerReputation,
    fa.QuestionIssueCategory,
    fa.FormattedQuestionTags,
    fa.TitleAlphaNumericLength,
    fa.HasStellarQuestionBadge,
    fa.CombinedOwnerReputation,
    fa.ScoreDifference,
    fa.TagCategory,
    'Potential Problematic Question' AS QuerySegmentType
FROM FinalAnalysis fa
WHERE COALESCE(fa.QuestionViewCount, 0) > 5000
  AND (fa.QuestionUpvoteRatio IS NULL OR fa.fa.QuestionUpvoteRatio < 0.6)
  AND COALESCE(fa.QuestionEditCount, 0) > 5
  AND COALESCE(fa.QuestionOwnerTotalPosts, 0) < 50
  AND COALESCE(fa.QuestionOwnerReputation, 0) < 1000
  AND (fa.IsClosed IS TRUE OR fa.IsCommunityWiki IS TRUE)
  AND COALESCE(fa.TitleAlphaNumericLength, 0) > 30
  AND COALESCE(fa.AnswerOwnerCommentsOnOwnAnswer, 0) > 0
  AND fa.QuestionTags IS NOT NULL
  AND fa.AnswerId IS NOT NULL; -- Must have an answer for this analysis
```