-- {"query": "1976.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2615} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserTotalUpVotes,
        u.DownVotes AS UserTotalDownVotes,
        u.Location,
        u.WebsiteUrl,
        COUNT(DISTINCT q.Id) AS QuestionsPostedCount,
        COUNT(DISTINCT a.Id) AS AnswersPostedCount,
        COUNT(DISTINCT c.Id) AS CommentsMadeCount,
        SUM(CASE WHEN p_all.PostTypeId = 1 THEN COALESCE(p_all.Score, 0) ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p_all.PostTypeId = 2 THEN COALESCE(p_all.Score, 0) ELSE 0 END) AS TotalAnswerScore,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(b.Date) AS LatestBadgeAwardDate,
        COUNT(b.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount
    FROM Users u
    LEFT JOIN Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1 -- Questions
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers
    LEFT JOIN Posts p_all ON u.Id = p_all.OwnerUserId -- All posts for scoring
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes, u.Location, u.WebsiteUrl
),
PostDetailsExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount, -- NULL logic
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.Title,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerIdOrDefault,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS PostUpvoteCount,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS PostDownvoteCount,
        -- Correlated subquery: check for specific editing patterns
        EXISTS (
            SELECT 1
            FROM PostHistory ph_mod
            WHERE ph_mod.PostId = p.Id
              AND ph_mod.PostHistoryTypeId IN (10, 11, 14, 15, 19, 20) -- Closed, Reopened, Locked, Unlocked, Protected, Unprotected
              AND ph_mod.UserId IS NOT NULL -- User-initiated moderator action
              AND ph_mod.CreationDate > p.CreationDate + INTERVAL '1 month' -- Moderator action after initial month
        ) AS HasDelayedModeratorAction,
        -- Correlated subquery: count distinct users who edited this post and are not the owner
        (SELECT COUNT(DISTINCT phe.UserId)
         FROM PostHistory phe
         WHERE phe.PostId = p.Id
           AND phe.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
           AND phe.UserId IS NOT NULL
           AND phe.UserId != p.OwnerUserId
        ) AS NonOwnerEditorCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
TagMetrics AS (
    SELECT
        pd.PostId,
        LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(pd.Tags FROM 2 FOR LENGTH(pd.Tags) - 2), '><')))) AS TagName, -- String expression
        pd.PostScore
    FROM PostDetailsExtended pd
    WHERE pd.Tags IS NOT NULL AND LENGTH(pd.Tags) > 2 -- Filter out malformed/empty tags
),
PostRelationshipSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Linked' THEN pl.RelatedPostId END) AS TotalLinkedPosts,
        COUNT(DISTINCT CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS TotalDuplicateSources,
        MAX(pl.CreationDate) AS LatestRelatedPostDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
RecentPostEvents AS (
    -- Set operator: UNION ALL to combine different types of recent post history events
    SELECT ph.PostId, 'Closed' AS EventType, ph.CreationDate AS EventDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND ph.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
    UNION ALL
    SELECT ph.PostId, 'Reopened' AS EventType, ph.CreationDate AS EventDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 11 -- Post Reopened
      AND ph.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
    UNION ALL
    SELECT ph.PostId, 'CommunityBump' AS EventType, ph.CreationDate AS EventDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 50 -- Community Bump
      AND ph.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    -- Complicated date calculation for user's account age in days
    EXTRACT(DAY FROM AGE(uas.LastAccessDate, uas.UserCreationDate)) AS UserAccountAgeDays,
    COALESCE(uas.Location, 'Unspecified Location') AS UserLocationNormalized, -- NULL logic
    LOWER(SPLIT_PART(SUBSTRING(uas.WebsiteUrl FROM '://([^/]+)'), '.', 1)) AS WebsiteSubdomain, -- Complex string parsing
    uas.QuestionsPostedCount,
    uas.AnswersPostedCount,
    uas.CommentsMadeCount,
    pde.PostId,
    pde.PostTypeName,
    pde.Title,
    pde.PostCreationDate,
    pde.PostScore,
    pde.ViewCount,
    pde.FavoriteCount,
    pde.PostUpvoteCount,
    pde.PostDownvoteCount,
    pde.NonOwnerEditorCount,
    pde.HasDelayedModeratorAction,
    prs.TotalLinkedPosts,
    prs.TotalDuplicateSources,
    -- Complicated calculation with NULLIF to prevent division by zero
    COALESCE(CAST(pde.PostUpvoteCount AS NUMERIC) / NULLIF(pde.PostUpvoteCount + pde.PostDownvoteCount, 0), 0.0) AS UpvoteSuccessRate,
    -- Window functions
    RANK() OVER (PARTITION BY COALESCE(uas.Location, 'N/A') ORDER BY uas.Reputation DESC, uas.LastAccessDate DESC) AS RankByUserReputationInLocation,
    AVG(pde.PostScore) OVER (PARTITION BY pde.PostTypeId ORDER BY pde.PostCreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreForType,
    LEAD(pde.PostCreationDate, 1, '9999-12-31'::timestamp) OVER (PARTITION BY uas.UserId ORDER BY pde.PostCreationDate) AS NextPostByCurrentUserDate,
    -- Aggregate string expression to list tags for each post
    (
        SELECT ARRAY_AGG(DISTINCT tm_agg.TagName ORDER BY tm_agg.TagName) FILTER (WHERE tm_agg.TagName IS NOT NULL)
        FROM TagMetrics tm_agg
        WHERE tm_agg.PostId = pde.PostId
        GROUP BY tm_agg.PostId
    ) AS PostTagsArray,
    -- Complicated CASE statement for Post Age Classification
    CASE
        WHEN pde.ClosedDate IS NOT NULL AND pde.CreationDate < CURRENT_DATE - INTERVAL '2 years' THEN 'Old & Closed'
        WHEN pde.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN pde.LastEditDate > pde.PostCreationDate + INTERVAL '1 year' AND pde.LastActivityDate > CURRENT_DATE - INTERVAL '3 months' THEN 'Actively Maintained Old Post'
        WHEN pde.CreationDate >= CURRENT_DATE - INTERVAL '6 months' THEN 'Recently Created'
        ELSE 'Mature & Stable'
    END AS PostAgeClassification,
    -- Correlated subquery using the RecentPostEvents CTE
    EXISTS (
        SELECT 1
        FROM RecentPostEvents rpe
        WHERE rpe.PostId = pde.PostId AND rpe.EventType = 'Reopened'
    ) AS WasRecentlyReopened,
    -- Another subquery for comparison: average reputation of users who answered this post
    (
        SELECT AVG(u_ans.Reputation)
        FROM Posts ans
        JOIN Users u_ans ON ans.OwnerUserId = u_ans.Id
        WHERE ans.ParentId = pde.PostId AND ans.PostTypeId = 2 AND u_ans.Reputation IS NOT NULL
    ) AS AvgAnswererReputation
FROM
    UserActivitySummary uas
LEFT JOIN
    PostDetailsExtended pde ON uas.UserId = pde.OwnerUserId
LEFT JOIN
    PostRelationshipSummary prs ON pde.PostId = prs.PostId
WHERE
    uas.Reputation >= 5000 -- Filter for established users
    AND pde.PostId IS NOT NULL -- Ensure only users with posts are considered in this context
    AND pde.PostTypeName IN ('Question', 'Answer') -- Focus on primary content types
    AND pde.PostCreationDate BETWEEN '2019-01-01' AND '2023-12-31' -- Specific date range for posts
    AND (pde.ViewCount > 1000 OR pde.FavoriteCount > 50 OR uas.TotalBadgesEarned > 10) -- High engagement/achievement filter
    AND pde.PostScore >= 5 -- Minimum post score
ORDER BY
    uas.Reputation DESC,
    pde.PostScore DESC,
    pde.PostCreationDate DESC,
    uas.UserId
;
