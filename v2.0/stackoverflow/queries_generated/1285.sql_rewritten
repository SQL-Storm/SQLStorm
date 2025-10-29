-- {"query": "1285.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2996} 
WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / (60 * 60 * 24) AS UserAgeDays,
        (u.UpVotes + u.DownVotes) AS TotalVotesCast,
        -- Calculate reputation growth per day, handling potential division by zero for very new users
        COALESCE(CAST(u.Reputation AS numeric) / NULLIF(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate)) / (60 * 60 * 24), 0), u.Reputation) AS ReputationPerDayApprox,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastEditorUserId,
        p.LastActivityDate,
        p.ClosedDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        -- Coalesce Title with a body excerpt if title is missing
        COALESCE(p.Title, SUBSTRING(p.Body, 1, 100)) AS PostTitleExcerpt,
        -- Parse tags into an array, handling NULL or empty tag strings
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
            THEN string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')
            ELSE NULL
        END AS ProcessedTagsArray,
        -- Determine if a post is accepted (either a question with an accepted answer or an answer that is accepted)
        CASE
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN TRUE
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL AND p.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = p.ParentId) THEN TRUE
            ELSE FALSE
        END AS IsAcceptedPost,
        EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - p.CreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        -- Calculate score per view, handling potential division by zero
        COALESCE(CAST(p.Score AS numeric) / NULLIF(p.ViewCount, 0), 0) AS ScorePerView,
        -- A calculated engagement score combining favorites, answers, and comments
        (COALESCE(p.FavoriteCount, 0) + COALESCE(p.AnswerCount, 0) * 2 + COALESCE(p.CommentCount, 0) * 0.5 + p.Score * 0.7) AS EngagementScoreBase
    FROM Posts AS p
    LEFT JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
),
PostEventTimeline AS (
    -- Aggregate key PostHistory events for each post
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.CreationDate END) AS InitialTitleDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.CreationDate END) AS InitialBodyDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastEditDateHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDateHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDateHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 12 THEN ph.CreationDate END) AS DeletedDateHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.CreationDate END) AS UndeletedDateHistory,
        MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS FirstEditDateHistory
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 11, 12, 13) -- Focus on relevant history types
    GROUP BY ph.PostId
),
AggregatedComments AS (
    -- Aggregate comment statistics per post
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountActual,
        AVG(CAST(c.Score AS numeric)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments AS c
    GROUP BY c.PostId
),
PostLinkAnalysis AS (
    -- Analyze linked and duplicate posts
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS TotalRelatedPosts,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostsCount
    FROM PostLinks AS pl
    GROUP BY pl.PostId
)
SELECT
    pd.PostId,
    pd.PostTypeName,
    pd.PostTitleExcerpt,
    pd.PostCreationDate,
    pd.PostAgeDays,
    pd.Score,
    pd.ViewCount,
    pd.ScorePerView,
    pd.IsAcceptedPost,
    pd.EngagementScoreBase,
    um_owner.DisplayName AS OwnerDisplayName,
    um_owner.Reputation AS OwnerReputation,
    um_owner.TotalBadges AS OwnerTotalBadges,
    um_owner.GoldBadges AS OwnerGoldBadges,
    um_owner.UserAgeDays AS OwnerUserAgeDays,
    um_editor.DisplayName AS LastEditorDisplayName,
    um_editor.Reputation AS LastEditorReputation,
    ac.CommentCountActual,
    ac.AvgCommentScore,
    -- Calculate age of the latest comment, defaulting to a high value if no comments
    COALESCE((EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - ac.LatestCommentDate)) / (60 * 60 * 24)), 99999) AS LatestCommentAgeDays,
    pet.InitialTitleDate,
    pet.FirstEditDateHistory,
    pet.LastEditDateHistory,
    pet.ClosedDateHistory,
    pet.ReopenedDateHistory,
    pet.DeletedDateHistory,
    pet.UndeletedDateHistory,
    -- Combine various dates to get a 'final' status date for the post
    COALESCE(pet.DeletedDateHistory, pet.ClosedDateHistory, pd.ClosedDate) AS FinalStatusDate,
    -- Rank posts by score and views within each post type
    RANK() OVER (PARTITION BY pd.PostTypeId ORDER BY pd.Score DESC, pd.ViewCount DESC) AS RankByScoreAndViews,
    -- Distribute posts into 10 engagement deciles
    NTILE(10) OVER (ORDER BY pd.EngagementScoreBase DESC) AS EngagementDecile,
    -- Find the creation date of the next and previous post by the same owner
    LEAD(pd.PostCreationDate, 1) OVER (PARTITION BY pd.OwnerUserId ORDER BY pd.PostCreationDate) AS NextPostByOwnerDate,
    LAG(pd.PostCreationDate, 1) OVER (PARTITION BY pd.OwnerUserId ORDER BY pd.PostCreationDate) AS PrevPostByOwnerDate,
    -- Calculate a 3-post moving average of score for each owner
    AVG(pd.Score) OVER (PARTITION BY pd.OwnerUserId ORDER BY pd.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS OwnerRecentAvgScore,
    -- Correlated subquery: count distinct related posts that are duplicates
    (
        SELECT COUNT(DISTINCT pl_sub.RelatedPostId)
        FROM PostLinks AS pl_sub
        WHERE pl_sub.PostId = pd.PostId
          AND pl_sub.LinkTypeId = 3 -- Duplicate link type
    ) AS DuplicateCountViaCorrelatedSubquery,
    pla.TotalRelatedPosts,
    pla.LinkedPostsCount,
    pla.DuplicatePostsCount,
    -- Categorize posts based on complex criteria involving tags, owner reputation, and engagement
    CASE
        WHEN pd.PostTypeId = 1 AND pd.ProcessedTagsArray IS NOT NULL AND 'sql' = ANY(pd.ProcessedTagsArray) THEN 'SQL_Question'
        WHEN pd.PostTypeId = 1 AND pd.ProcessedTagsArray IS NOT NULL AND 'python' = ANY(pd.ProcessedTagsArray) THEN 'Python_Question'
        WHEN pd.PostTypeId = 2 AND um_owner.Reputation > 10000 AND pd.Score > 50 AND pd.IsAcceptedPost THEN 'High_Impact_Accepted_Answer'
        WHEN pd.PostAgeDays > 365 AND pd.Score = 0 AND ac.CommentCountActual IS NULL THEN 'Stale_Unnoticed_Post'
        WHEN pd.ClosedDate IS NOT NULL AND pet.ReopenedDateHistory IS NOT NULL THEN 'Closed_Then_Reopened'
        ELSE 'Other_Category'
    END AS PostCategoryFlag,
    -- Determine the most effective last activity date
    COALESCE(
        pd.LastActivityDate,
        pet.LastEditDateHistory,
        ac.LatestCommentDate,
        pd.PostCreationDate
    ) AS EffectiveLastActivityDate,
    -- Calculate days from creation to close, handling NULLs
    COALESCE(EXTRACT(EPOCH FROM (COALESCE(pet.ClosedDateHistory, pd.ClosedDate) - pd.PostCreationDate)) / (60 * 60 * 24), -1) AS DaysToCloseOrMinusOne,
    -- Correlated subquery: sum all bounty amounts for a post
    (
        SELECT
            SUM(v.BountyAmount)
        FROM Votes AS v
        WHERE v.PostId = pd.PostId
          AND v.VoteTypeId = 8 -- BountyStart vote type
    ) AS TotalBountyAmount,
    -- Complex string manipulation for a transformed title
    UPPER(SUBSTRING(pd.PostTitleExcerpt FROM 1 FOR 1)) ||
    COALESCE(REPLACE(SUBSTRING(pd.PostTitleExcerpt FROM 2 FOR LENGTH(pd.PostTitleExcerpt) - 3), ' ', '_'), '') ||
    LOWER(SUBSTRING(pd.PostTitleExcerpt FROM LENGTH(pd.PostTitleExcerpt) - 1 FOR 2)) AS TitleStringTransform
FROM
    PostDetails AS pd
LEFT JOIN UserMetrics AS um_owner ON pd.OwnerUserId = um_owner.UserId
LEFT JOIN UserMetrics AS um_editor ON pd.LastEditorUserId = um_editor.UserId
LEFT JOIN AggregatedComments AS ac ON pd.PostId = ac.PostId
LEFT JOIN PostEventTimeline AS pet ON pd.PostId = pet.PostId
LEFT JOIN PostLinkAnalysis AS pla ON pd.PostId = pla.PostId
WHERE
    pd.PostTypeName IN ('Question', 'Answer') -- Focus on core content types
    AND pd.PostCreationDate >= '2020-01-01' -- Filter for more recent activity
    AND (pd.ViewCount > 500 OR pd.Score > 20) -- Only include posts with some level of engagement
    AND (
        (um_owner.Reputation > 5000 AND um_owner.GoldBadges > 0) -- High-reputation owner with gold badges
        OR (ac.AvgCommentScore IS NOT NULL AND ac.AvgCommentScore > 2.5) -- Posts with good comments
        OR (pd.IsAcceptedPost = TRUE AND pd.AnswerCount > 0 AND pd.FavoriteCount > 10) -- Accepted answers with favorites
    )
    -- Exclude posts that are duplicates of more than one other post (non-correlated subquery)
    AND pd.PostId NOT IN (
        SELECT pl_exclusion.PostId
        FROM PostLinks AS pl_exclusion
        WHERE pl_exclusion.LinkTypeId = 3
        GROUP BY pl_exclusion.PostId
        HAVING COUNT(pl_exclusion.RelatedPostId) > 1
    )
ORDER BY
    pd.PostCreationDate DESC, pd.EngagementScoreBase DESC, pd.ViewCount DESC
LIMIT 5000;