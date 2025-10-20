-- {"query": "19007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2992} 

WITH UserEngagementSummary AS (
    -- Summarizes user statistics, including post counts, scores, and badge information.
    -- Uses LEFT JOIN to ensure all users are included, even those without specific post types or badges.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS TotalProfileViews,
        u.UpVotes AS TotalUpvotesGiven,
        u.DownVotes AS TotalDownvotesGiven,
        COUNT(DISTINCT q.Id) FILTER (WHERE q.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswersPosted,
        SUM(q.Score) AS TotalQuestionScore,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(q.ViewCount) AS AvgQuestionViewCount,
        MAX(COALESCE(q.LastActivityDate, a.LastActivityDate, u.LastAccessDate)) AS LatestActivityDateByUser,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgesCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgesCount,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgesCount
    FROM Users u
    LEFT JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
QuestionEditAnalysis AS (
    -- Analyzes the edit history for questions, calculating time differences between edits
    -- and numbering edits for each post using window functions.
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate)) AS TimeSincePreviousEdit,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_edit,
        COUNT(ph.Id) OVER (PARTITION BY ph.PostId) AS TotalEditsForPost
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostCommentActivity AS (
    -- Aggregates comment statistics for posts, including total comments, score, length,
    -- and a simple sentiment analysis based on keywords.
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        COUNT(c.Id) FILTER (WHERE c.Text ILIKE '%great%' OR c.Text ILIKE '%thanks%' OR c.Text ILIKE '%helpful%') AS PositiveComments,
        COUNT(c.Id) FILTER (WHERE c.Text ILIKE '%bug%' OR c.Text ILIKE '%issue%' OR c.Text ILIKE '%wrong%') AS NegativeComments,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
TaggedPostDetails AS (
    -- Extracts tags for questions and joins with the Tags table to get tag-specific information.
    -- Uses UNNEST and string_to_array for tag parsing, as described in the schema.
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        p.Score,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName,
        t.Id AS TagId,
        t.Count AS TagUseCount,
        (t.ExcerptPostId IS NOT NULL OR t.WikiPostId IS NOT NULL) AS HasTagWikiContent
    FROM Posts p
    JOIN Tags t ON TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) = t.TagName
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
)
-- Main Query: Combines insights from CTEs, applies complex filtering, joins, subqueries, and window functions.
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.QuestionsPosted,
    ues.AnswersPosted,
    ues.TotalQuestionScore,
    ues.TotalAnswerScore,
    ues.GoldBadgesCount,
    -- Complicated calculation for an "Influence Score" incorporating various user metrics.
    CAST(
        (ues.Reputation * 0.15) +
        (COALESCE(ues.AvgQuestionViewCount, 0) * 0.02) +
        (COALESCE(ues.TotalAnswerScore, 0) * 0.25) +
        (ues.GoldBadgesCount * 12) +
        (ues.SilverBadgesCount * 3) -
        (ues.TotalDownvotesGiven * 0.05)
    AS NUMERIC(10, 2)) AS InfluenceScore,
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    p.ViewCount AS QuestionViews,
    p.AnswerCount AS QuestionAnswers,
    p.CreationDate AS QuestionCreationDate,
    COALESCE(p.LastEditDate, p.CreationDate) AS LastContentUpdate,
    -- String expressions and NULL logic for processing the question title.
    CASE
        WHEN p.Title IS NULL THEN 'NO TITLE AVAILABLE'
        WHEN LENGTH(p.Title) < 30 THEN 'SHORT_TITLE: ' || UPPER(SUBSTRING(p.Title FROM 1 FOR 25))
        ELSE 'STANDARD_TITLE: ' || UPPER(SUBSTRING(TRIM(p.Title) FROM 1 FOR 50))
    END AS ProcessedTitleFragment,
    -- Correlated subquery: Calculates the average score of other questions posted by the same user.
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = ues.UserId AND p2.PostTypeId = 1 AND p2.Id != p.Id AND p2.CreationDate < p.CreationDate) AS AvgPreviousQuestionScoreByUser,
    -- Window function: Ranks questions by view count within each user's questions.
    DENSE_RANK() OVER (PARTITION BY ues.UserId ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS UserQuestionViewRank,
    qa.TotalEditsForPost,
    qa.TimeSincePreviousEdit AS LatestEditInterval,
    pca.TotalComments,
    pca.AvgCommentLength,
    pca.PositiveComments,
    pca.NegativeComments,
    tpd.TagName AS TopTagName,
    tpd.HasTagWikiContent,
    -- Conditional check using EXISTS: identifies community-owned questions related to 'sql' tag.
    EXISTS (
        SELECT 1
        FROM PostLinks pl
        JOIN Posts related_p ON pl.RelatedPostId = related_p.Id
        WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1 -- Linked posts
          AND related_p.CommunityOwnedDate IS NOT NULL
          AND EXISTS (SELECT 1 FROM TaggedPostDetails tpd_inner WHERE tpd_inner.PostId = related_p.Id AND tpd_inner.TagName = 'sql')
    ) AS HasLinkedCommunityOwnedSqlPost,
    -- Date arithmetic and CASE for categorizing post activity.
    CASE
        WHEN p.LastActivityDate > (NOW() - INTERVAL '3 months') THEN 'Very Recent'
        WHEN p.LastActivityDate BETWEEN (NOW() - INTERVAL '6 months') AND (NOW() - INTERVAL '3 months') THEN 'Recent'
        WHEN p.LastActivityDate BETWEEN (NOW() - INTERVAL '1 year') AND (NOW() - INTERVAL '6 months') THEN 'Moderate'
        ELSE 'Old'
    END AS ActivityCategory
FROM UserEngagementSummary ues
INNER JOIN Posts p ON ues.UserId = p.OwnerUserId
LEFT JOIN (SELECT PostId, EditorUserId, EditDate, TimeSincePreviousEdit, TotalEditsForPost FROM QuestionEditAnalysis WHERE rn_latest_edit = 1) qa
    ON p.Id = qa.PostId
LEFT JOIN PostCommentActivity pca ON p.Id = pca.PostId
LEFT JOIN TaggedPostDetails tpd ON p.Id = tpd.PostId
    AND tpd.TagUseCount = (SELECT MAX(TagUseCount) FROM TaggedPostDetails WHERE PostId = p.Id) -- Correlated subquery for the most used tag on the post
WHERE
    p.PostTypeId = 1 -- Focus on questions
    AND ues.Reputation >= 2500 -- Highly reputable users
    AND ues.QuestionsPosted >= 10 -- Users with significant question activity
    AND p.ViewCount > 1000 -- Popular questions
    AND p.Score >= 10 -- Well-received questions
    AND (
        p.AcceptedAnswerId IS NOT NULL OR -- Has an accepted answer
        (p.AnswerCount > 2 AND p.FavoriteCount >= 5) OR -- Or has multiple answers and favorites
        (p.ClosedDate IS NULL AND p.CommunityOwnedDate IS NULL AND p.CreationDate > (NOW() - INTERVAL '2 years')) -- Or is an active, relatively recent question
    )
    AND (pca.TotalComments IS NULL OR pca.TotalComments >= 3) -- NULL logic: Include if no comments or at least 3 comments
    AND qa.TotalEditsForPost IS NOT NULL -- Must have at least one edit history entry
    AND qa.EditorUserId IS NOT NULL -- Ensure editor is identifiable

UNION ALL -- Set operator: Combines with a filtered list of users who primarily post answers, for comparative analysis.
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.QuestionsPosted,
    ues.AnswersPosted,
    ues.TotalQuestionScore,
    ues.TotalAnswerScore,
    ues.GoldBadgesCount,
    -- Recalculated Influence Score, weighted more towards answers for this group.
    CAST(
        (ues.Reputation * 0.18) +
        (COALESCE(ues.TotalAnswerScore, 0) * 0.35) +
        (ues.GoldBadgesCount * 15) -
        (ues.TotalDownvotesGiven * 0.08)
    AS NUMERIC(10, 2)) AS InfluenceScore,
    NULL AS QuestionId,
    'N/A - Answer-Focused User' AS QuestionTitle,
    NULL AS QuestionViews,
    ues.AnswersPosted AS QuestionAnswers, -- Represents answer count for this context
    NULL AS QuestionCreationDate,
    ues.LatestActivityDateByUser AS LastContentUpdate,
    'ANSWER_ONLY_PROFILE' AS ProcessedTitleFragment,
    (SELECT AVG(a_sub.Score) FROM Posts a_sub WHERE a_sub.OwnerUserId = ues.UserId AND a_sub.PostTypeId = 2) AS AvgAnswerScoreByUser, -- Subquery for average answer score
    NULL AS UserQuestionViewRank,
    NULL AS TotalEditsForPost,
    NULL AS LatestEditInterval,
    NULL AS TotalComments,
    NULL AS AvgCommentLength,
    NULL AS PositiveComments,
    NULL AS NegativeComments,
    NULL AS TopTagName,
    FALSE AS HasTagWikiContent,
    FALSE AS HasLinkedCommunityOwnedSqlPost,
    CASE
        WHEN ues.LatestActivityDateByUser > (NOW() - INTERVAL '6 months') THEN 'Recent'
        ELSE 'Old'
    END AS ActivityCategory
FROM UserEngagementSummary ues
WHERE
    ues.QuestionsPosted < 5 -- Users who primarily post answers
    AND ues.AnswersPosted >= 20 -- With a significant number of answers
    AND ues.Reputation >= 1500 -- Reputable answerers
    AND ues.GoldBadgesCount > 0 -- Users with at least one gold badge
    AND ues.LatestActivityDateByUser > (NOW() - INTERVAL '1 year') -- Recently active
ORDER BY InfluenceScore DESC, Reputation DESC, LastContentUpdate DESC
LIMIT 1500;
