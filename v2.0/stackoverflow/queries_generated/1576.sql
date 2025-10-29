-- {"query": "1576.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2327} 

WITH RecentHighRepUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        NTILE(5) OVER (ORDER BY u.Reputation DESC) AS ReputationQuintile,
        CASE
            WHEN u.Location LIKE '%USA%' OR u.Location LIKE '%United States%' THEN 'USA'
            WHEN u.Location LIKE '%Canada%' THEN 'Canada'
            WHEN u.Location IS NULL OR u.Location = '' THEN 'Unknown'
            ELSE 'Other'
        END AS UserRegionCategory,
        -- Correlated subquery to count gold badges
        (SELECT COUNT(DISTINCT b.Name) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgesCount
    FROM
        Users u
    WHERE
        u.Reputation >= 1000
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '90 days'
        AND u.DisplayName IS NOT NULL
),
PostDetailsAggregated AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title AS PostTitle,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS ActualAnswerCount,
        COALESCE(p.CommentCount, 0) AS ActualCommentCount,
        COALESCE(p.FavoriteCount, 0) AS ActualFavoriteCount,
        p.AcceptedAnswerId,
        p.Tags,
        -- Correlated subquery for last comment date
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS LastCommentDate,
        -- Correlated subquery for total bounty amount
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS TotalBountyAmount,
        -- Filtered aggregation for edit user count
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditUserCount,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS LastEditDateHistory
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.CreationDate >= CURRENT_DATE - INTERVAL '180 days' -- Only recent posts
        AND p.PostTypeId IN (1, 2) -- Questions or Answers
        AND p.Score > 0
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId, p.Tags
),
TagPerformanceMetrics AS ( -- This CTE now directly creates a row per Post-Tag association
    SELECT
        pa.PostId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(pa.Tags FROM 2 FOR LENGTH(pa.Tags)-2), '><')) AS TagName,
        pa.PostScore,
        pa.PostViewCount,
        pa.ActualAnswerCount,
        pa.ActualCommentCount,
        pa.ActualFavoriteCount,
        pa.OwnerUserId
    FROM
        PostDetailsAggregated pa
    WHERE
        pa.Tags IS NOT NULL AND LENGTH(pa.Tags) > 2
),
AggregatedTagStats AS (
    SELECT
        tp.TagName,
        COUNT(DISTINCT tp.PostId) AS TotalTaggedPosts,
        SUM(tp.PostViewCount) AS TotalTagViews,
        AVG(tp.PostScore) AS AverageTagScore,
        COUNT(DISTINCT tp.OwnerUserId) AS UniqueContributorsToTag,
        -- Correlated subquery for duplicate linked posts specific to this tag
        (
            SELECT COUNT(DISTINCT pl.RelatedPostId)
            FROM PostLinks pl
            INNER JOIN TagPerformanceMetrics tpm_linked ON pl.PostId = tpm_linked.PostId
            WHERE tpm_linked.TagName = tp.TagName -- Correlates with the outer CTE's TagName
            AND pl.LinkTypeId = 3 -- Duplicate link type
        ) AS DuplicateLinkedPostsCount
    FROM
        TagPerformanceMetrics tp
    GROUP BY
        tp.TagName
    HAVING
        COUNT(DISTINCT tp.PostId) > 10 -- Only consider tags with significant activity
)
SELECT
    rhu.UserName,
    rhu.Reputation,
    rhu.UserRegionCategory,
    rhu.GoldBadgesCount,
    pa.PostTitle,
    pa.PostCreationDate,
    pa.PostScore,
    pa.PostViewCount,
    pa.ActualAnswerCount,
    pa.ActualCommentCount,
    pa.ActualFavoriteCount,
    ats.TagName AS AssociatedTagName,
    ats.TotalTaggedPosts,
    ats.TotalTagViews,
    ats.AverageTagScore,
    -- Complicated calculation: Score per thousand views
    ROUND((CAST(pa.PostScore AS NUMERIC) / NULLIF(pa.PostViewCount, 0)) * 1000, 2) AS ScorePerThousandViews,
    -- Window function: Rank posts within each user by score
    DENSE_RANK() OVER (PARTITION BY rhu.UserId ORDER BY pa.PostScore DESC, pa.PostViewCount DESC) AS RankWithinUserPosts,
    -- Window function: Average post score for each user
    AVG(pa.PostScore) OVER (PARTITION BY rhu.UserId) AS AvgUserPostScore,
    -- Window function: Rolling sum of answers for a user's last 4 posts
    SUM(pa.ActualAnswerCount) OVER (PARTITION BY rhu.UserId ORDER BY pa.PostCreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS RollingAnswersLast4Posts,
    -- Correlated subquery with string concatenation and existence check for user's tag badge status
    COALESCE(
        (SELECT 'Has "gold-' || b.Name || '" badge'
         FROM Badges b
         WHERE b.UserId = rhu.UserId
           AND b.Class = 1
           AND b.TagBased = TRUE
           AND b.Name = ats.TagName -- Assuming tag-based gold badges have names matching the tag (e.g., 'java', not 'gold-java')
           -- Ensure the user actually posted on this specific tag in the relevant post
           AND EXISTS (
               SELECT 1 FROM TagPerformanceMetrics tpm_badge
               WHERE tpm_badge.PostId = pa.PostId
               AND tpm_badge.TagName = ats.TagName
               AND tpm_badge.OwnerUserId = rhu.UserId
           )
         LIMIT 1),
        'No specific gold badge for this tag'
    ) AS UserTagBadgeStatus,
    -- Complex CASE statement for post engagement status
    CASE
        WHEN pa.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
        WHEN pa.PostTypeId = 1 AND pa.ActualAnswerCount = 0 THEN 'No Answers Yet'
        WHEN pa.PostTypeId = 2 AND pa.PostScore > 5 THEN 'High Score Answer'
        ELSE 'Other'
    END AS PostEngagementStatus,
    ph_close.CreationDate AS PostClosedDate,
    crt.Name AS CloseReason,
    -- Correlated subquery for the latest comment text
    (SELECT c_latest.Text FROM Comments c_latest WHERE c_latest.PostId = pa.PostId ORDER BY c_latest.CreationDate DESC LIMIT 1) AS LatestCommentText,
    -- String expression: shortened title snippet
    LOWER(LEFT(pa.PostTitle, 20)) || (CASE WHEN LENGTH(pa.PostTitle) > 20 THEN '...' ELSE '' END) AS ShortenedTitleSnippet,
    -- Complicated expression with GREATEST and COALESCE
    GREATEST(pa.PostScore, pa.PostViewCount / 100, COALESCE(pa.ActualFavoriteCount, 0) * 10) AS EngagementMetric
FROM
    RecentHighRepUsers rhu
INNER JOIN PostDetailsAggregated pa ON rhu.UserId = pa.OwnerUserId
INNER JOIN TagPerformanceMetrics tpm ON pa.PostId = tpm.PostId
INNER JOIN AggregatedTagStats ats ON tpm.TagName = ats.TagName
LEFT JOIN PostHistory ph_close ON pa.PostId = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
LEFT JOIN CloseReasonTypes crt ON ph_close.Comment = crt.Id::text -- Assuming Comment stores CloseReasonId as string
WHERE
    pa.PostCreationDate BETWEEN rhu.CreationDate AND rhu.LastAccessDate -- Post creation within user's active period
    AND (pa.PostScore > 5 OR pa.PostViewCount > 100) -- Predicate with OR
    AND pa.ActualCommentCount >= 1
    AND ats.TotalTagViews > 1000
    AND rhu.ReputationQuintile IN (1, 2) -- Predicate with IN
    AND (rhu.UserRegionCategory = 'USA' OR rhu.GoldBadgesCount > 0) -- Predicate with complex OR logic
    -- Correlated subquery with EXISTS for recent upvotes
    AND EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = pa.PostId
        AND v.VoteTypeId = 2 -- UpMod
        AND v.CreationDate BETWEEN CURRENT_DATE - INTERVAL '60 days' AND CURRENT_DATE
        AND v.UserId IS NOT NULL -- NULL logic: only considering votes from actual users
    )
ORDER BY
    rhu.Reputation DESC,
    pa.PostCreationDate DESC,
    ScorePerThousandViews DESC
LIMIT 500;
