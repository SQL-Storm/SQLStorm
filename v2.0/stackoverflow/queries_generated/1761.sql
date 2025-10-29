-- {"query": "1761.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2847} 
WITH UserActivitySummary AS (
    -- Summarize user activity, vote counts, and badge achievements, handling potential NULLs for non-existent activities
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotesGiven
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    -- Calculate detailed engagement for posts, including distinct editors and historical activity counts
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate) AS LatestEditDate,
        COUNT(ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS CloseVoteHistoryCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS IsClosed
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId, p.ClosedDate
),
PostCloseHistory AS (
    -- Identify the latest close reason for each post, if any, using a window function
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseHistoryDate,
        ph.Comment AS CloseReasonId_str,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) -- Post Closed history types
),
AggregatedTagStats AS (
    -- Aggregate statistics for popular tags, joining to the Tags table for canonical names
    SELECT
        t.TagName,
        COUNT(DISTINCT p_tag_link.Id) AS TotalQuestionsWithTag,
        AVG(p_tag_link.Score) AS AverageScoreForTag,
        SUM(p_tag_link.ViewCount) AS TotalViewsForTag
    FROM Tags t
    JOIN Posts p_tag_link ON p_tag_link.PostTypeId = 1 -- Only questions have tags in this context
    CROSS JOIN LATERAL string_to_array(SUBSTRING(p_tag_link.Tags, 2, LENGTH(p_tag_link.Tags) - 2), '><') AS tag_array_inner(TagName_Inner)
    WHERE tag_array_inner.TagName_Inner = t.TagName
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT p_tag_link.Id) > 50 -- Focus on more widely used tags
),
RankedPosts AS (
    -- Rank posts by score and view count within their post type for recent activity, and compare sequential post scores by owner
    SELECT
        pem.PostId,
        pem.PostTypeId,
        pem.OwnerUserId,
        pem.PostCreationDate,
        pem.Score,
        pem.ViewCount,
        pem.AnswerCount,
        pem.CommentCount,
        pem.FavoriteCount,
        pem.DistinctEditors,
        pem.LatestEditDate,
        pem.TotalHistoryEntries,
        pem.HasAcceptedAnswer,
        pem.IsClosed,
        RANK() OVER (PARTITION BY pem.PostTypeId ORDER BY pem.Score DESC, pem.ViewCount DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY pem.PostTypeId ORDER BY pem.LatestEditDate DESC, pem.Score DESC) AS LatestActivityRank,
        LAG(pem.Score, 1, 0) OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostCreationDate) AS PrevPostScoreByOwner,
        LEAD(pem.Score, 1, 0) OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostCreationDate) AS NextPostScoreByOwner,
        AVG(pem.Score) OVER (PARTITION BY pem.OwnerUserId) AS OwnerAvgPostScore,
        COUNT(pem.Id) OVER (PARTITION BY pem.OwnerUserId) AS OwnerTotalPosts
    FROM PostEngagementMetrics pem
    WHERE pem.PostCreationDate >= NOW() - INTERVAL '2 year' -- Only consider recent posts
    AND pem.Score > 0 -- Exclude zero-score posts
),
UserCommentPreference AS (
    -- Identify users who tend to comment more than they ask questions
    SELECT UserId FROM Comments
    GROUP BY UserId
    HAVING COUNT(Id) > 5 AND COUNT(DISTINCT PostId) > 2 -- Significant commenting activity
    EXCEPT -- Exclude users who have also asked questions
    SELECT OwnerUserId FROM Posts WHERE PostTypeId = 1
    GROUP BY OwnerUserId
    HAVING COUNT(Id) > 0
)
-- Main query to analyze influential users and high-impact posts, incorporating diverse SQL constructs
SELECT
    uas.UserId,
    COALESCE(uas.DisplayName, 'Deleted User') AS UserDisplayName, -- Handle NULL DisplayName
    uas.Reputation,
    uas.UserCreationDate,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalCommentsMade,
    uas.TotalBadges,
    uas.UserTotalUpVotes,
    uas.UserTotalDownVotes,
    uas.AcceptedVotesGiven,
    uas.UserProfileViews,
    rp.PostId,
    pt.Name AS PostTypeName,
    p.Title,
    p.Tags,
    rp.PostCreationDate,
    rp.Score AS PostScore,
    rp.ViewCount AS PostViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    rp.FavoriteCount AS PostFavoriteCount,
    rp.DistinctEditors,
    rp.LatestEditDate,
    rp.TotalHistoryEntries,
    rp.HasAcceptedAnswer,
    rp.IsClosed,
    (rp.Score::NUMERIC / NULLIF(rp.ViewCount, 0)) AS ScorePerViewRatio, -- Ratio with NULL handling
    (rp.Score::NUMERIC / NULLIF(rp.OwnerAvgPostScore, 0)) AS ScoreRatioToOwnerAverage,
    rp.ScoreRank,
    rp.LatestActivityRank,
    rp.PrevPostScoreByOwner,
    rp.NextPostScoreByOwner,
    -- Correlated subquery: Compare current post's score to the average of other recent posts by the same owner
    (SELECT AVG(p2.Score)
     FROM Posts p2
     WHERE p2.OwnerUserId = uas.UserId
       AND p2.Id <> rp.PostId
       AND p2.CreationDate BETWEEN rp.PostCreationDate - INTERVAL '6 month' AND rp.PostCreationDate + INTERVAL '6 month'
       AND p2.PostTypeId = rp.PostTypeId
    ) AS AvgOtherRecentPostScoreByOwner,
    ptags.TagName AS AssociatedTagName, -- Tag name from the lateral join
    COALESCE(ats.AverageScoreForTag, 0) AS AverageTagScore,
    COALESCE(ats.TotalQuestionsWithTag, 0) AS QuestionsInTag,
    CASE
        WHEN uas.Reputation > 5000 AND rp.Score > 50 AND rp.DistinctEditors > 1 AND rp.PostTypeId = 1 THEN 'Highly Influential Question'
        WHEN uas.Reputation > 2000 AND rp.HasAcceptedAnswer = 1 AND rp.PostTypeId = 2 AND rp.PostScore > rp.PrevPostScoreByOwner THEN 'Valuable Answerer (Improving Trend)'
        WHEN rp.LatestEditDate >= NOW() - INTERVAL '1 month' AND rp.Score > 10 AND CHAR_LENGTH(COALESCE(p.Body, '')) > 500 THEN 'Recently Active & Elaborate Post'
        WHEN uas.UserId IN (SELECT UserId FROM UserCommentPreference) THEN 'Active Commenter, Not Primary Questioner' -- Uses the result of an EXCEPT CTE
        WHEN p.ClosedDate IS NOT NULL AND crt.Name IS NOT NULL AND LOWER(crt.Name) LIKE '%duplicate%' THEN 'Closed Post (Duplicate)'
        ELSE 'General Contributor'
    END AS UserPostImpactCategory,
    LENGTH(COALESCE(p.Body, '')) AS PostBodyLength, -- String expression for body length
    LENGTH(COALESCE(p.Title, '')) AS PostTitleLength, -- String expression for title length
    phc.CloseHistoryDate,
    crt.Name AS CloseReason -- Close reason from PostHistory join
FROM UserActivitySummary uas
INNER JOIN RankedPosts rp ON uas.UserId = rp.OwnerUserId
INNER JOIN Posts p ON rp.PostId = p.Id
INNER JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN LATERAL ( -- CROSS JOIN LATERAL to unnest tags, potentially generating multiple rows per post
    SELECT TRIM(tag_name) AS TagName
    FROM string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS tag_array(tag_name)
    WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
) AS ptags ON TRUE
LEFT JOIN AggregatedTagStats ats ON ptags.TagName = ats.TagName
LEFT JOIN PostCloseHistory phc ON p.Id = phc.PostId AND phc.rn = 1 -- Join for latest close reason
LEFT JOIN CloseReasonTypes crt ON crt.Id = CASE
    WHEN phc.CloseReasonId_str ~ '^\d+$' THEN CAST(phc.CloseReasonId_str AS SMALLINT) -- Robust cast from string to smallint
    ELSE NULL
END
WHERE
    uas.Reputation > 750 -- Filter for more established users
    AND rp.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND p.Title IS NOT NULL AND p.Body IS NOT NULL -- Ensure content exists
    AND rp.Score >= 5 -- Filter for reasonably scored posts
    AND rp.LatestActivityRank <= 250 -- Limit to top 250 most recently active posts of each type
    AND (ptags.TagName IS NULL OR ptags.TagName LIKE '%sql%' OR ptags.TagName LIKE '%python%') -- Filter by specific tag interests
ORDER BY
    uas.Reputation DESC,
    rp.PostScore DESC,
    rp.LatestEditDate DESC,
    p.Title
LIMIT 500;