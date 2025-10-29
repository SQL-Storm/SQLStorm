-- {"query": "1247.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3122} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user activity and engagement metrics, focusing on their posting behavior
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Views, 0) AS TotalProfileViews,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL AND p.Score > 0) AS AvgPositivePostScore, -- Only positive scores
        SUM(p.FavoriteCount) AS TotalFavoriteCounts,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
    HAVING
        COUNT(p.Id) >= 10 -- Only consider users with at least 10 posts
        AND u.Reputation > 500 -- Users with meaningful reputation
),
PostDetailsExtended AS (
    -- CTE 2: Provides detailed post metrics including votes, comments, and sophisticated history flags
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        MAX(ph_edit.CreationDate) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4, 5, 6)) AS LastContentEditDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        EXISTS (
            -- Correlated subquery: Check if post has ever been explicitly reopened
            SELECT 1
            FROM PostHistory ph_reopen
            WHERE ph_reopen.PostId = p.Id
              AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
              AND ph_reopen.CreationDate > p.CreationDate
        ) AS WasReopened,
        EXISTS (
            -- Correlated subquery: Check if post was ever closed by a specific reason (e.g., duplicate)
            SELECT 1
            FROM PostHistory ph_close
            WHERE ph_close.PostId = p.Id
              AND ph_close.PostHistoryTypeId = 10 -- Post Closed
              AND ph_close.Comment IN ('1', '101') -- Specific close reasons: Exact Duplicate or Duplicate
        ) AS WasDuplicateClosed,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600 AS HoursSinceCreationActive, -- Time in hours
        COALESCE(p.CommunityOwnedDate IS NOT NULL, FALSE) AS IsCommunityOwned
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph_edit ON p.Id = ph_edit.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.Title, p.Tags, p.ClosedDate, p.LastActivityDate, p.CommunityOwnedDate
    HAVING
        COALESCE(p.ViewCount, 0) > 100 -- Ensure posts have some visibility
),
TagPerformance AS (
    -- CTE 3: Processes tags to calculate aggregated statistics and ranks them
    SELECT
        TRIM(REPLACE(REPLACE(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')), '&lt;', '<'), '&gt;', '>')) AS TagName,
        p.Id AS PostId,
        p.Score AS PostScore,
        p.ViewCount,
        p.CreationDate
    FROM
        Posts p
    WHERE
        p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.PostTypeId = 1 -- Only questions have relevant tags
),
AggregatedTagStats AS (
    -- CTE 4: Aggregates statistics per tag and assigns a rank based on engagement
    SELECT
        tp.TagName,
        COUNT(tp.PostId) AS TaggedPostsCount,
        AVG(tp.PostScore) FILTER (WHERE tp.PostScore IS NOT NULL) AS AvgTagPostScore,
        SUM(tp.ViewCount) AS TotalTagViewCount,
        MAX(tp.CreationDate) AS LatestPostInTag,
        DENSE_RANK() OVER (ORDER BY SUM(tp.ViewCount) DESC, COUNT(tp.PostId) DESC) AS TagEngagementRank
    FROM
        TagPerformance tp
    GROUP BY
        tp.TagName
    HAVING
        COUNT(tp.PostId) > 50 -- Only consider active tags with sufficient posts
        AND SUM(tp.ViewCount) > 1000 -- And significant total views
),
BadgeEliteUsers AS (
    -- CTE 5: Identifies users with a substantial number of high-tier named badges
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalNamedBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM
        Badges b
    WHERE
        b.TagBased = FALSE -- Focus on named badges, not tag-specific ones
    GROUP BY
        b.UserId
    HAVING
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) >= 2 OR SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) >= 10 -- At least 2 Gold OR 10 Silver badges
),
ComplicatedCommentAnalysis AS (
    -- CTE 6: Analyzes comments for a post, looking for specific patterns and user engagement
    SELECT
        c.PostId,
        COUNT(DISTINCT c.UserId) AS DistinctCommenters,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN c.Text LIKE '%bug%' OR c.Text LIKE '%error%' THEN 1 ELSE 0 END) AS ProblemKeywordsInComments,
        (CAST(SUM(c.Score) AS NUMERIC) / NULLIF(COUNT(c.Id), 0)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Comments c
    WHERE
        c.CreationDate >= '2020-01-01' -- Recent comments
    GROUP BY
        c.PostId
),
PostLinkHistory AS (
    -- CTE 7: Examines post links to identify related content and duplicates
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateLinksCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM
        PostLinks pl
    GROUP BY
        pl.PostId
)
-- Main Query: Combines all CTEs to generate a comprehensive report on influential posts and users within "hot" or "challenging" topics
SELECT
    ue.DisplayName AS UserName,
    ue.Reputation,
    pde.PostId,
    pde.Title AS PostTitle,
    pde.PostCreationDate,
    pde.PostScore,
    pde.ViewCount,
    pde.AnswerCount,
    pde.CommentCount,
    pde.UpVotesReceived,
    pde.DownVotesReceived,
    pde.Tags,
    pde.WasReopened,
    pde.WasDuplicateClosed,
    ats.TagName AS PrimaryTagName,
    ats.AvgTagPostScore,
    ats.TotalTagViewCount,
    beu.GoldBadges,
    beu.SilverBadges,
    cca.DistinctCommenters,
    cca.ProblemKeywordsInComments,
    plh.LinkedPostsCount,
    plh.DuplicateLinksCount,
    -- Complex calculation for "InfluenceMetric": Combines user reputation, post score, vote ratio, and comment activity
    (
        CAST(ue.Reputation AS NUMERIC) * pde.PostScore
        * (pde.UpVotesReceived + 1) / GREATEST(pde.DownVotesReceived + 1, 1) -- Avoid division by zero
        * (1 + COALESCE(cca.DistinctCommenters, 0) * 0.1) -- Boost for comments
        * (CASE WHEN pde.WasReopened THEN 1.5 ELSE 1 END) -- Boost for reopened posts
        * (CASE WHEN pde.IsCommunityOwned THEN 0.8 ELSE 1 END) -- Slightly reduce for community owned
    ) AS InfluenceMetric,
    pde.HoursSinceCreationActive,
    CASE
        WHEN pde.PostTypeId = 1 AND pde.WasReopened AND pde.AnswerCount = 0 THEN 'ChallengingQuestion_NoAcceptedAnswer'
        WHEN pde.PostTypeId = 1 AND pde.WasReopened AND pde.AcceptedAnswerId IS NOT NULL THEN 'ReevaluatedQuestion_AcceptedAnswer'
        WHEN pde.PostTypeId = 2 AND pde.PostScore > 100 THEN 'HighlyValuedAnswer'
        WHEN pde.ClosedDate IS NOT NULL AND pde.WasDuplicateClosed THEN 'ClosedAsDuplicate'
        WHEN pde.ClosedDate IS NOT NULL AND pde.WasReopened = FALSE THEN 'StagnantClosedPost'
        WHEN pde.ViewCount > 5000 AND pde.CommentCount > 20 THEN 'HighActivityDiscussion'
        ELSE 'GeneralActivePost'
    END AS PostStatusCategory,
    -- Window function: Ranks posts by InfluenceMetric within their primary tag group
    RANK() OVER (PARTITION BY ats.TagName ORDER BY (ue.Reputation * pde.PostScore * (pde.UpVotesReceived + 1) / GREATEST(pde.DownVotesReceived + 1, 1)) DESC, pde.ViewCount DESC) AS RankWithinPrimaryTag
FROM
    UserEngagement ue
INNER JOIN
    PostDetailsExtended pde ON ue.UserId = pde.OwnerUserId
LEFT JOIN LATERAL ( -- Lateral join to find the best performing tag for the post
    SELECT tp.TagName, ats_inner.AvgTagPostScore, ats_inner.TotalTagViewCount
    FROM TagPerformance tp
    INNER JOIN AggregatedTagStats ats_inner ON tp.TagName = ats_inner.TagName
    WHERE tp.PostId = pde.PostId
    ORDER BY ats_inner.TagEngagementRank ASC
    LIMIT 1
) ats ON TRUE
FULL OUTER JOIN -- Full Outer Join to ensure we capture all elite users, even if they don't have posts matching other criteria
    BadgeEliteUsers beu ON ue.UserId = beu.UserId
LEFT JOIN
    ComplicatedCommentAnalysis cca ON pde.PostId = cca.PostId
LEFT JOIN
    PostLinkHistory plh ON pde.PostId = plh.PostId
WHERE
    pde.PostCreationDate >= '2021-01-01' -- Filter for relatively recent posts
    AND pde.PostTypeId IN (1, 2) -- Only questions or answers
    AND pde.HoursSinceCreationActive > 72 -- Active for at least 3 days
    AND (pde.Title LIKE '%SQL%' OR pde.Title LIKE '%database%' OR pde.Body LIKE '%performance tuning%' OR pde.Tags LIKE '%<sql-server>%') -- Specific topic relevance
    AND (
        pde.WasReopened = TRUE
        OR pde.PostScore >= 25
        OR cca.ProblemKeywordsInComments >= 1 -- Posts with detected "problem" keywords in comments
        OR plh.DuplicateLinksCount >= 1 -- Posts linked as duplicates
        OR beu.GoldBadges >= 1 -- User has at least one gold badge (after FULL OUTER JOIN)
    )
    AND ue.DisplayName IS NOT NULL -- Exclude posts from deleted users or those without display names
    AND NOT EXISTS ( -- Correlated NOT EXISTS subquery to exclude posts with any moderator locking history
        SELECT 1
        FROM PostHistory ph_modlock
        WHERE ph_modlock.PostId = pde.PostId
          AND ph_modlock.PostHistoryTypeId IN (14, 15) -- Post Locked or Unlocked
    )
ORDER BY
    InfluenceMetric DESC NULLS LAST, pde.ViewCount DESC, beu.GoldBadges DESC NULLS LAST, ats.TagEngagementRank ASC NULLS LAST
LIMIT 500;
