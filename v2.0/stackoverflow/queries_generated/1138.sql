-- {"query": "1138.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2761} 

WITH UserBaseStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.Views AS UserViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        MAX(p.LastActivityDate) AS LatestPostActivityDate -- Aggregated max for the user
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostDetailsBase AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.FavoriteCount,
        p.ClosedDate,
        -- Complex expression: Calculate a "Post Engagement Ratio"
        CAST(p.Score AS NUMERIC) / NULLIF(p.ViewCount + p.CommentCount + COALESCE(p.FavoriteCount, 0) + 1, 0) AS EngagementRatio,
        -- Extract tags as an array, handling NULLs
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN
                string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')
            ELSE ARRAY[]::VARCHAR[]
        END AS TagArray
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
PostWindowFunctions AS (
    SELECT
        pdb.PostId,
        -- Window function: Rank posts by score within each PostType
        ROW_NUMBER() OVER (PARTITION BY pdb.PostTypeId ORDER BY pdb.PostScore DESC, pdb.PostCreationDate DESC) AS PostScoreRank,
        -- Window function: Calculate average score of all posts created within the same month as this post
        AVG(CAST(pdb.PostScore AS NUMERIC)) OVER (PARTITION BY EXTRACT(YEAR FROM pdb.PostCreationDate), EXTRACT(MONTH FROM pdb.PostCreationDate)) AS MonthlyAvgPostScore,
        -- Window function: Lag for previous post activity date for a given post owner
        LAG(pdb.LastActivityDate, 1, pdb.CreationDate) OVER (PARTITION BY pdb.OwnerUserId ORDER BY pdb.CreationDate) AS PreviousPostActivityDate
    FROM PostDetailsBase pdb
),
PostTagAggregations AS (
    SELECT
        PostId,
        COUNT(DISTINCT unnest_tag.TagName) AS UniqueTagsOnPost,
        STRING_AGG(DISTINCT unnest_tag.TagName, ', ') AS AllTagsOnPost
    FROM PostDetailsBase
    CROSS JOIN LATERAL unnest(TagArray) AS unnest_tag(TagName)
    WHERE CARDINALITY(TagArray) > 0
    GROUP BY PostId
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS HistoryCreationDate,
        ph.UserId AS HistoryEditorUserId,
        ph.Text AS HistoryText,
        ph.Comment AS HistoryComment,
        pht.Name AS HistoryTypeName,
        -- Window function to get the most recent edit body for a post
        LAST_VALUE(ph.Text) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS LatestBodyRevision,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
),
ClosedQuestionDetails AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDate,
        crt.Name AS CloseReason,
        (
            SELECT COUNT(DISTINCT elem)
            FROM jsonb_array_elements_text(COALESCE(ph.Text::jsonb, '{}'::jsonb) -> 'OriginalQuestionIds') AS elem
            WHERE ph.Text IS NOT NULL AND ph.Text ~ '.*"OriginalQuestionIds":\s*\[.*].*'
        ) AS DuplicateQuestionCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.Comment IS NOT NULL AND ph.PostHistoryTypeId = 10 AND crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
)
SELECT
    ubs.UserId,
    COALESCE(ubs.DisplayName, 'Deleted User') AS UserDisplayName,
    ubs.Reputation,
    ubs.UserCreationDate,
    ubs.UserLastAccessDate,
    EXTRACT(DAY FROM AGE(NOW(), ubs.UserCreationDate)) AS DaysSinceUserCreation,
    ubs.TotalPosts,
    ubs.TotalQuestions,
    ubs.TotalAnswers,
    ubs.TotalPostScore,
    ubs.TotalPostViews,
    ubs.TotalComments,
    ubs.TotalCommentScore,
    ubs.LatestPostActivityDate,
    ubs.UserUpVotes,
    ubs.UserDownVotes,
    ubs.UserViews,
    -- User Badge Summary
    COALESCE(ubs_badge.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs_badge.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs_badge.BronzeBadges, 0) AS BronzeBadges,
    -- Primary Post Details
    pdb.PostId,
    pdb.PostTypeName,
    pdb.PostCreationDate,
    pdb.PostScore,
    pdb.ViewCount,
    pdb.AnswerCount,
    pdb.CommentCount,
    pdb.Title,
    pdb.FavoriteCount,
    pdb.EngagementRatio,
    pwf.PostScoreRank,
    pwf.MonthlyAvgPostScore,
    pwf.PreviousPostActivityDate, -- From Window functions
    -- Correlated subquery: Get the most upvoted comment text for this post
    (SELECT c.Text FROM Comments c WHERE c.PostId = pdb.PostId ORDER BY c.Score DESC, c.CreationDate DESC LIMIT 1) AS TopCommentText,
    -- Correlated subquery: Get the average score of answers to this specific question (if it's a question)
    (SELECT AVG(a_sub.Score) FROM Posts a_sub WHERE a_sub.ParentId = pdb.PostId AND a_sub.PostTypeId = 2) AS AvgAnswerScoreForQuestion,
    -- Details from PostHistory
    rph.HistoryCreationDate AS LastEditDate,
    rph.HistoryEditorUserId AS LastEditorOfPostBody,
    rph.LatestBodyRevision AS LastKnownPostBodyRevision,
    -- Close reason details for questions
    cqd.CloseReason,
    cqd.DuplicateQuestionCount,
    -- Post Link info: Check if post is a source of duplicate links
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = pdb.PostId AND pl.LinkTypeId = 3) AS IsDuplicateSource,
    -- Tag related information
    pta.UniqueTagsOnPost,
    pta.AllTagsOnPost,
    -- Complex NULL logic and conditional filtering
    CASE
        WHEN pdb.PostTypeId = 1 AND pdb.ClosedDate IS NOT NULL AND cqd.CloseReason ILIKE '%duplicate%' THEN 'Closed-Duplicate-Question'
        WHEN pdb.PostTypeId = 1 AND pdb.ClosedDate IS NOT NULL THEN 'Closed-Question'
        WHEN pdb.PostTypeId = 1 AND pdb.AnswerCount > 0 AND pdb.AcceptedAnswerId IS NOT NULL THEN 'Answered-Accepted-Question'
        WHEN pdb.PostTypeId = 2 AND pdb.PostScore > (SELECT AVG(p_inner.Score) FROM Posts p_inner WHERE p_inner.PostTypeId = 2) THEN 'High-Score-Answer'
        WHEN pdb.PostTypeId = 2 AND pdb.ParentId IS NULL THEN 'Orphan-Answer-Suspicious' -- Should not happen in real data, but good for testing NULL logic
        ELSE 'Other-Active-Post'
    END AS PostStatusClassifier,
    -- Elaborate calculation involving user and post data
    (ubs.Reputation * (COALESCE(pdb.PostScore, 0) + COALESCE(pdb.FavoriteCount, 0) * 2 - ubs.UserDownVotes * 0.1) + ubs.UserUpVotes * 0.5) / NULLIF(ubs.TotalPosts + ubs.TotalComments + 1, 0) AS UserPostInfluenceScore
FROM
    UserBaseStats ubs
LEFT JOIN UserBadgeSummary ubs_badge ON ubs.UserId = ubs_badge.UserId
LEFT JOIN PostDetailsBase pdb ON ubs.UserId = pdb.OwnerUserId
LEFT JOIN PostWindowFunctions pwf ON pdb.PostId = pwf.PostId
LEFT JOIN RecentPostHistory rph ON pdb.PostId = rph.PostId AND rph.rn = 1 -- Only the most recent history entry
LEFT JOIN ClosedQuestionDetails cqd ON pdb.PostId = cqd.PostId AND pdb.PostTypeId = 1 -- Only for questions (PostTypeId = 1)
LEFT JOIN PostTagAggregations pta ON pdb.PostId = pta.PostId
WHERE
    ubs.Reputation >= 500 -- Base reputation filter
    AND ubs.TotalPosts > 5 -- Minimum post count
    AND pdb.PostCreationDate IS NOT NULL -- Ensure posts exist for filtering
    AND (
        pdb.PostScore >= 10 -- High score
        OR pdb.ViewCount >= 1000 -- High view count
        OR EXISTS (SELECT 1 FROM Comments cm WHERE cm.PostId = pdb.PostId AND LENGTH(cm.Text) > 100 AND cm.Score > 0) -- Significant comments
    )
    AND NOT EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = pdb.PostId AND v.VoteTypeId = 12 AND v.CreationDate > NOW() - INTERVAL '1 year') -- Exclude recently spam-voted posts
    AND (ubs.UserViews > 100 OR ubs.UserUpVotes > 50) -- Additional user engagement filter
ORDER BY
    UserPostInfluenceScore DESC,
    pdb.PostScore DESC,
    ubs.Reputation DESC,
    cqd.DuplicateQuestionCount DESC NULLS LAST
LIMIT 1000;
