-- {"query": "1446.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3099} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        AVG(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersGiven,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / 31536000.0 AS UserAgeYears, -- User age in years (approx)
        COALESCE(u.UpVotes * 1.0 / NULLIF(u.DownVotes, 0), u.UpVotes) AS UpDownVoteRatio,
        -- Correlated subquery: average score of posts *before* a certain date, filtered by content
        (SELECT AVG(s.Score) FROM Posts s WHERE s.OwnerUserId = u.Id AND s.CreationDate < u.CreationDate + INTERVAL '1 year' AND LENGTH(s.Body) > 100) AS AvgScoreFirstYearLongPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostHistoricalMetrics AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteCount,
        MAX(ph.CreationDate) AS LastHistoryDate,
        MIN(ph.CreationDate) AS FirstHistoryDate,
        -- Find the last non-null close reason comment
        SUBSTRING(
            MAX(
                CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL THEN ph.CreationDate::text || ph.Comment ELSE NULL END
            ) FROM 20
        )::smallint AS LastCloseReasonTypeId, -- Assumes timestamp is 19 chars long
        -- Window function: Date difference to the previous edit for a post
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 3600 AS HoursSincePreviousEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1,2,3,4,5,6,10,11,12,13,14,15,19,20) -- Focus on key history events, including protected/unprotected
    GROUP BY ph.PostId, ph.CreationDate -- Need to include CreationDate for LAG to work correctly over the original rows, then group in the outer query
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        COUNT(t.TagName) AS DistinctTagCount,
        STRING_AGG(t.TagName, ', ') AS AllTagsConcatenated,
        LOWER(COALESCE(SUBSTRING(p.Tags, 2, POSITION('><' IN p.Tags) - 2), 'untagged')) AS PrimaryTag,
        MAX(CASE WHEN t.IsModeratorOnly = TRUE THEN 1 ELSE 0 END) AS HasModeratorOnlyTag,
        -- Window function: Rank tags by their count across all posts
        RANK() OVER (ORDER BY COUNT(t.TagName) DESC) AS PrimaryTagPopularityRank
    FROM Posts p
    LEFT JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_list(TagName_Raw) ON p.Tags IS NOT NULL
    LEFT JOIN Tags t ON tag_list.TagName_Raw = t.TagName
    WHERE p.Tags IS NOT NULL
    GROUP BY p.Id, p.Tags
),
PostLinkRelationships AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinkCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Linked') AS LinkedPostCount,
        AVG(CASE WHEN lt.Name = 'Duplicate' THEN rp.Score ELSE NULL END) AS AvgDuplicateScore,
        MAX(CASE WHEN lt.Name = 'Linked' THEN rp.ViewCount ELSE NULL END) AS MaxLinkedViewCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts rp ON pl.RelatedPostId = rp.Id -- Related Post
    GROUP BY p.Id
),
CombinedPostData AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        ue.Reputation,
        ue.UserAgeYears,
        ue.TotalQuestionsAsked,
        ue.TotalAnswersGiven,
        phm.TotalHistoryEvents,
        phm.EditCount,
        phm.CloseCount,
        phm.ReopenCount,
        phm.DeleteCount,
        phm.LastCloseReasonTypeId,
        crt.Name AS LastCloseReasonTypeName,
        phm.HoursSincePreviousEdit,
        pra.DistinctTagCount,
        pra.PrimaryTag,
        pra.HasModeratorOnlyTag,
        plr.DuplicateLinkCount,
        plr.LinkedPostCount,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.LastActivityDate,
        -- Complex calculation: Post Quality Metric
        (p.Score * 0.5 + p.ViewCount * 0.01 + COALESCE(p.AnswerCount, 0) * 2 + COALESCE(p.FavoriteCount, 0) * 5 + p.CommentCount * 0.5 + ue.AvgPostScore * 0.1) *
        (1 - COALESCE(phm.DeleteCount, 0) * 0.8 - COALESCE(phm.CloseCount, 0) * 0.5) AS PostQualityMetric,
        -- String expression and NULL logic: Sanitize title
        COALESCE(REPLACE(TRIM(p.Title), '?', ''), 'Untitled Post') AS CleanTitle,
        -- Check if it's an accepted answer for its parent question
        EXISTS (
            SELECT 1 FROM Posts parent_q WHERE parent_q.Id = p.ParentId AND parent_q.AcceptedAnswerId = p.Id
        ) AS IsAcceptedAnswer,
        -- Window function: Rank posts by their quality metric within their primary tag
        NTILE(4) OVER (PARTITION BY pra.PrimaryTag ORDER BY (p.Score + p.ViewCount) DESC) AS PrimaryTagEngagementQuadrant,
        -- Window function: Moving average of score for posts by the same user
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS OwnerRecentAvgScore
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN UserEngagement ue ON p.OwnerUserId = ue.UserId
    LEFT JOIN PostHistoricalMetrics phm ON p.Id = phm.PostId
    LEFT JOIN CloseReasonTypes crt ON phm.LastCloseReasonTypeId = crt.Id
    LEFT JOIN PostTagAnalysis pra ON p.Id = pra.PostId
    LEFT JOIN PostLinkRelationships plr ON p.Id = plr.PostId
    WHERE p.OwnerUserId IS NOT NULL
      AND p.CreationDate >= NOW() - INTERVAL '4 years'
      AND LENGTH(COALESCE(p.Body, '')) > 50 -- Filter for meaningful posts
      AND (p.Score >= 5 OR p.ViewCount >= 500 OR p.AnswerCount >= 1) -- Basic activity filter
),
FlaggedContentCandidates AS (
    SELECT
        cp.PostId,
        cp.PostTypeName,
        cp.CleanTitle,
        cp.OwnerUserId,
        cp.Reputation,
        cp.PostQualityMetric,
        cp.CloseCount,
        cp.ReopenCount,
        cp.LastCloseReasonTypeName,
        cp.PrimaryTag,
        cp.DuplicateLinkCount,
        cp.HasModeratorOnlyTag,
        -- Further categorization based on combined metrics
        CASE
            WHEN cp.CloseCount > 0 AND cp.ReopenCount = 0 AND cp.DuplicateLinkCount > 0 THEN 'Closed_Duplicate_NoReopen'
            WHEN cp.PostQualityMetric < 0 AND cp.EditCount > 3 THEN 'LowQuality_HighEdit_Redo'
            WHEN cp.PostTypeId = 1 AND cp.AnswerCount = 0 AND cp.CommentCount > 5 AND cp.PostCreationDate < NOW() - INTERVAL '1 year' THEN 'Unanswered_Discussed_Stale'
            WHEN cp.HasModeratorOnlyTag = 1 AND cp.CloseCount = 0 THEN 'ModeratorTag_Open'
            ELSE 'Standard_Interesting'
        END AS ContentFlagCategory
    FROM CombinedPostData cp
    WHERE cp.PostQualityMetric < 10 OR cp.CloseCount > 0 OR cp.DuplicateLinkCount > 0 OR cp.HasModeratorOnlyTag = 1
)
-- Final union of two distinct analysis views to demonstrate set operations and complex filtering
SELECT
    'High_Engagement_Insights' AS AnalysisType,
    fcc.PostId,
    fcc.PostTypeName,
    fcc.CleanTitle,
    fcc.Reputation,
    fcc.PostQualityMetric,
    fcc.PrimaryTag,
    fcc.ContentFlagCategory,
    cbd.IsAcceptedAnswer,
    cbd.OwnerRecentAvgScore,
    cbd.HoursSincePreviousEdit,
    NULL AS PotentialMigrationTarget
FROM FlaggedContentCandidates fcc
INNER JOIN CombinedPostData cbd ON fcc.PostId = cbd.PostId -- Re-join to get more details for the final select
WHERE fcc.ContentFlagCategory IN ('Standard_Interesting', 'ModeratorTag_Open')
  AND cbd.PostQualityMetric > 15
  AND cbd.PrimaryTagEngagementQuadrant IN (1, 2)
  AND (
        (cbd.PostTypeId = 1 AND cbd.AnswerCount > 0 AND cbd.PostCreationDate > NOW() - INTERVAL '2 years') OR
        (cbd.PostTypeId = 2 AND cbd.IsAcceptedAnswer = TRUE AND cbd.Score > 10)
      )

UNION ALL

SELECT
    'Problematic_Historical_Analysis' AS AnalysisType,
    fcc.PostId,
    fcc.PostTypeName,
    fcc.CleanTitle,
    fcc.Reputation,
    fcc.PostQualityMetric,
    fcc.PrimaryTag,
    fcc.ContentFlagCategory,
    cbd.IsAcceptedAnswer,
    cbd.OwnerRecentAvgScore,
    cbd.HoursSincePreviousEdit,
    -- Complicated expression: Suggest potential migration target based on historical close reasons and duplicate links
    COALESCE(
        CASE
            WHEN fcc.LastCloseReasonTypeName = 'Off-topic' AND fcc.DuplicateLinkCount = 0 THEN 'StackOverflow-Meta'
            WHEN fcc.DuplicateLinkCount > 0 AND cbd.PostTypeId = 1 AND cbd.AnswerCount = 0 THEN 'Related_Question_Merge'
            ELSE NULL
        END, 'No_Specific_Target'
    ) AS PotentialMigrationTarget
FROM FlaggedContentCandidates fcc
INNER JOIN CombinedPostData cbd ON fcc.PostId = cbd.PostId
WHERE fcc.ContentFlagCategory IN ('Closed_Duplicate_NoReopen', 'LowQuality_HighEdit_Redo', 'Unanswered_Discussed_Stale')
  AND cbd.PostCreationDate < NOW() - INTERVAL '1 year'
  AND (cbd.Score < 5 OR cbd.ViewCount < 100)
  AND cbd.OwnerUserId IS NOT NULL AND cbd.Reputation < 500 -- Filter for posts by less experienced users

ORDER BY AnalysisType, PostQualityMetric DESC, PostId
LIMIT 5000;
