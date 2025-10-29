-- {"query": "1727.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3445} 
WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(AVG(p.Score * 1.0), 0) AS AvgOverallPostScore, -- Ensure float division
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation
),
PostHistoryAgg AS (
    SELECT
        ph.PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS LastEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.UserId ELSE NULL END) AS DistinctEditors,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 'Closed' ELSE 'Open' END) AS PostStatus,
        -- Use COALESCE for NULL logic if Comment is sometimes NULL but needed for CloseReasonTypeId
        COALESCE(MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment SIMILAR TO '[0-9]+' THEN CAST(ph.Comment AS int) ELSE NULL END), -1) AS LastCloseReasonTypeId
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL -- Exclude community posts for owner-centric analysis
    GROUP BY ph.PostId, p.PostTypeId, pt.Name, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.OwnerUserId
),
PostLinkSummary AS (
    SELECT
        pl.PostId AS SourcePostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE NULL END) AS OutgoingLinksCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE NULL END) AS OutgoingDuplicateCount,
        -- Correlated subquery to get total score of linked posts
        (SELECT COALESCE(SUM(p_linked.Score), 0) FROM Posts p_linked WHERE p_linked.Id IN (SELECT pl_inner.RelatedPostId FROM PostLinks pl_inner WHERE pl_inner.PostId = pl.PostId)) AS SumLinkedPostScores
    FROM PostLinks pl
    GROUP BY pl.PostId
),
UserActivityRank AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.TotalQuestions,
        ups.TotalAnswers,
        ups.AvgOverallPostScore,
        ups.TotalCommentsMade,
        ups.LatestPostDate,
        ups.EarliestPostDate,
        pha.PostId,
        pha.PostTypeName AS PostType,
        pha.PostCreationDate,
        pha.PostScore,
        pha.ViewCount,
        pha.Title,
        pha.Tags,
        pha.EditCount,
        pha.DistinctEditors,
        pha.PostStatus,
        pha.LastCloseReasonTypeId,
        COALESCE(pha.LastEditDate, pha.PostCreationDate) AS EffectiveLastActivityDate, -- NULL Logic
        EXTRACT(EPOCH FROM (pha.LastEditDate - pha.PostCreationDate)) / 3600.0 AS TimeToFirstEditHours, -- Date calculation, float result
        ROW_NUMBER() OVER (PARTITION BY ups.UserId ORDER BY pha.PostCreationDate DESC) AS rn_latest_post_per_user,
        AVG(pha.PostScore) OVER (PARTITION BY ups.UserId, pha.PostTypeName) AS AvgPostScoreByTypeForUser,
        RANK() OVER (PARTITION BY ups.UserId ORDER BY pha.ViewCount DESC, pha.PostScore DESC) AS PostEngagementRank,
        LAG(pha.PostCreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY ups.UserId ORDER BY pha.PostCreationDate) AS PreviousPostDate, -- LAG with default
        STRING_TO_ARRAY(SUBSTRING(pha.Tags, 2, LENGTH(pha.Tags)-2), '><') AS TagArray -- String expression
    FROM UserPostStats ups
    JOIN PostHistoryAgg pha ON ups.UserId = pha.OwnerUserId
    WHERE ups.TotalPosts > 5 AND ups.Reputation > 100 -- Filtering for relevant users
)
SELECT
    uar.UserId,
    uar.DisplayName,
    uar.Reputation,
    uar.TotalPosts,
    uar.TotalQuestions,
    uar.TotalAnswers,
    uar.AvgOverallPostScore,
    uar.TotalCommentsMade,
    uar.PostId,
    uar.PostType,
    uar.Title,
    uar.PostScore,
    uar.ViewCount,
    uar.EditCount,
    uar.DistinctEditors,
    uar.PostStatus,
    uar.LastCloseReasonTypeId,
    uar.EffectiveLastActivityDate,
    uar.TimeToFirstEditHours,
    uar.AvgPostScoreByTypeForUser,
    uar.PostEngagementRank,
    -- Complicated calculation: total activity span in hours
    (EXTRACT(DAY FROM (uar.LatestPostDate - uar.EarliestPostDate)) * 24 + EXTRACT(HOUR FROM (uar.LatestPostDate - uar.EarliestPostDate))) AS UserActivitySpanHours,
    -- Outer Join with Badges
    COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
    COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
    COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
    MAX(b.Date) AS MostRecentBadgeAwarded,
    pls.OutgoingLinksCount,
    pls.OutgoingDuplicateCount,
    pls.SumLinkedPostScores,
    -- Correlated Subquery for latest user comment on *this specific post*
    (
        SELECT c.Text
        FROM Comments c
        WHERE c.UserId = uar.UserId
          AND c.PostId = uar.PostId
          AND c.CreationDate < NOW() -- Predicate for performance/relevance
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS LatestCommentOnOwnPost,
    -- Complicated predicate and string operations with Tags using UNNEST and ILIKE
    CASE
        WHEN EXISTS (SELECT 1 FROM UNNEST(uar.TagArray) AS tag WHERE tag ILIKE '%sql%' OR tag ILIKE '%database%' OR tag ILIKE '%server%') THEN 'Database-related'
        WHEN EXISTS (SELECT 1 FROM UNNEST(uar.TagArray) AS tag WHERE tag ILIKE '%javascript%' OR tag ILIKE '%python%' OR tag ILIKE '%java%' OR tag ILIKE '%c#%') THEN 'Programming-related'
        WHEN EXISTS (SELECT 1 FROM UNNEST(uar.TagArray) AS tag WHERE tag ILIKE '%linux%' OR tag ILIKE '%windows%' OR tag ILIKE '%os%') THEN 'OS-related'
        ELSE 'Other'
    END AS TagCategory,
    -- More complex calculation: ratio of answers to questions, handling division by zero (NULL logic)
    NULLIF(CAST(uar.TotalAnswers AS DECIMAL) / NULLIF(uar.TotalQuestions, 0), 0) AS AnswerToQuestionRatio,
    -- Another window function: NTILE for reputation distribution across the result set
    NTILE(10) OVER (ORDER BY uar.Reputation DESC) AS ReputationDecile,
    -- Example of an elaborate conditional expression with date comparisons
    CASE
        WHEN uar.PostCreationDate > uar.PreviousPostDate + INTERVAL '1 month' THEN 'Long Gap'
        WHEN uar.PostCreationDate <= uar.PreviousPostDate + INTERVAL '1 day' THEN 'Frequent Posting'
        ELSE 'Regular Posting'
    END AS PostingFrequencyPattern
FROM UserActivityRank uar
LEFT JOIN Badges b ON uar.UserId = b.UserId
LEFT JOIN PostLinkSummary pls ON uar.PostId = pls.SourcePostId
WHERE uar.rn_latest_post_per_user = 1 -- Only consider the latest post for each user in this main branch for aggregation
  AND uar.PostStatus = 'Open' -- Only open posts
  AND uar.TimeToFirstEditHours IS NOT NULL
  AND uar.PostEngagementRank <= 3 -- Top 3 engaged posts for that user
  AND uar.Title IS NOT NULL AND LENGTH(TRIM(uar.Title)) > 10 -- String expression, predicate
GROUP BY
    uar.UserId, uar.DisplayName, uar.Reputation, uar.TotalPosts, uar.TotalQuestions, uar.TotalAnswers,
    uar.AvgOverallPostScore, uar.TotalCommentsMade, uar.PostId, uar.PostType, uar.Title,
    uar.PostScore, uar.ViewCount, uar.EditCount, uar.DistinctEditors, uar.PostStatus,
    uar.LastCloseReasonTypeId, uar.EffectiveLastActivityDate, uar.TimeToFirstEditHours,
    uar.AvgPostScoreByTypeForUser, uar.PostEngagementRank, uar.LatestPostDate, uar.EarliestPostDate,
    pls.OutgoingLinksCount, pls.OutgoingDuplicateCount, pls.SumLinkedPostScores,
    uar.TagArray, uar.PreviousPostDate -- TagArray needs to be grouped if it's used in the SELECT list, even implicitly via UNNEST in a CASE.
    -- Or, better, extract TagCategory into a separate CTE if it affects grouping logic in a complex way.
    -- For EXISTS check, Postgres allows it to not be in GROUP BY as it's a scalar evaluation per row before grouping.
    -- However, for the sake of explicit grouping in complex queries, including it if derived directly.
UNION ALL -- Set operator to combine different analytical views
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COALESCE(AVG(p.Score * 1.0), 0) AS AvgOverallPostScore,
    COUNT(DISTINCT c.Id) AS TotalCommentsMade,
    null::int as PostId,
    null::varchar(50) as PostType,
    null::varchar(300) as Title,
    null::int as PostScore,
    null::int as ViewCount,
    null::bigint as EditCount,
    null::bigint as DistinctEditors,
    null::varchar(6) as PostStatus,
    null::smallint as LastCloseReasonTypeId,
    null::timestamp as EffectiveLastActivityDate,
    null::float as TimeToFirstEditHours,
    null::float as AvgPostScoreByTypeForUser,
    null::bigint as PostEngagementRank,
    (EXTRACT(DAY FROM (MAX(p.CreationDate) - MIN(p.CreationDate))) * 24 + EXTRACT(HOUR FROM (MAX(p.CreationDate) - MIN(p.CreationDate)))) AS UserActivitySpanHours,
    COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
    COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
    COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
    MAX(b.Date) AS MostRecentBadgeAwarded,
    0 AS OutgoingLinksCount, -- Default for this branch
    0 AS OutgoingDuplicateCount, -- Default for this branch
    0 AS SumLinkedPostScores, -- Default for this branch
    -- Correlated subquery for users who commented on posts that got many downvotes
    (SELECT c_inner.Text
     FROM Comments c_inner
     JOIN Posts p_inner ON c_inner.PostId = p_inner.Id
     WHERE c_inner.UserId = u.Id AND p_inner.Score < -5 -- Example threshold
     ORDER BY c_inner.CreationDate DESC LIMIT 1) AS LatestCommentOnOwnPost,
    'High Downvote Activity' AS TagCategory,
    NULLIF(CAST(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0), 0) AS AnswerToQuestionRatio,
    NTILE(10) OVER (ORDER BY u.Reputation DESC) AS ReputationDecile,
    'N/A - Summary' AS PostingFrequencyPattern
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v_down ON u.Id = v_down.UserId AND v_down.VoteTypeId = 3
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.Reputation < 500
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(v_down.Id) > 10 -- Users who have given at least 10 downvotes
ORDER BY Reputation DESC, UserActivitySpanHours DESC;