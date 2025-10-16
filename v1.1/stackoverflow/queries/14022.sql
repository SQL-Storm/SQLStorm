WITH cte AS (
    SELECT 
        p.Id, 
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.Title,
        p.Body,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.Score,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus,
        CASE
            WHEN p.OwnerUserId IS NULL THEN 'Community'
            ELSE u.DisplayName
        END AS OwnerDisplayName,
        COALESCE(
            CASE WHEN p.ClosedDate IS NOT NULL THEN CAST(p.ClosedDate AS timestamp) - CAST(p.CreationDate AS timestamp) END,
            CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN CAST(p.CommunityOwnedDate AS timestamp) - CAST(p.CreationDate AS timestamp) END,
            CAST('2024-10-01 12:34:56' AS timestamp) - CAST(p.CreationDate AS timestamp)
        ) AS DaysSinceCreation_interval,
        COALESCE(
            CASE WHEN p.ClosedDate IS NOT NULL THEN CAST(p.ClosedDate AS timestamp) - CAST(p.CreationDate AS timestamp) ELSE INTERVAL '0' END
        ) AS DaysUntilClosed_interval,
        COALESCE(
            CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN CAST(p.CommunityOwnedDate AS timestamp) - CAST(p.CreationDate AS timestamp) ELSE INTERVAL '0' END
        ) AS DaysUntilCommunityOwned_interval,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph
             WHERE ph.PostId = p.Id
             AND ph.PostHistoryTypeId IN (10, 11, 12, 13)),
            0
        ) AS NumClosureEvents,
        COALESCE(
            (SELECT COUNT(*)
             FROM Votes v
             WHERE v.PostId = p.Id
             AND v.VoteTypeId = 2),
            0
        ) AS NumUpvotes,
        COALESCE(
            (SELECT COUNT(*)
             FROM Votes v
             WHERE v.PostId = p.Id
             AND v.VoteTypeId = 3),
            0
        ) AS NumDownvotes,
        COALESCE(
            (SELECT COUNT(*)
             FROM Comments c
             WHERE c.PostId = p.Id),
            0
        ) AS NumComments,
        COALESCE(
            (SELECT COUNT(*)
             FROM PostLinks pl
             WHERE pl.PostId = p.Id
             AND pl.LinkTypeId = 3),
            0
        ) AS NumDuplicates
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
cte_numeric AS (
    SELECT
        Id,
        PostTypeId,
        OwnerUserId,
        CreationDate,
        ClosedDate,
        CommunityOwnedDate,
        Title,
        Body,
        Tags,
        AnswerCount,
        CommentCount,
        FavoriteCount,
        ViewCount,
        Score,
        PostStatus,
        OwnerDisplayName,
        -- convert intervals to number of days (fractional)
        EXTRACT(EPOCH FROM DaysSinceCreation_interval) / 86400.0 AS DaysSinceCreation,
        EXTRACT(EPOCH FROM DaysUntilClosed_interval) / 86400.0 AS DaysUntilClosed,
        EXTRACT(EPOCH FROM DaysUntilCommunityOwned_interval) / 86400.0 AS DaysUntilCommunityOwned,
        NumClosureEvents,
        NumUpvotes,
        NumDownvotes,
        NumComments,
        NumDuplicates
    FROM cte
),
agg AS (
    SELECT
        PostTypeId,
        PostStatus,
        OwnerDisplayName,
        COUNT(*) AS NumPosts,
        AVG(DaysSinceCreation) AS AvgDaysSinceCreation,
        AVG(DaysUntilClosed) AS AvgDaysUntilClosed,
        AVG(DaysUntilCommunityOwned) AS AvgDaysUntilCommunityOwned,
        AVG(NumClosureEvents) AS AvgNumClosureEvents,
        AVG(NumUpvotes) AS AvgNumUpvotes,
        AVG(NumDownvotes) AS AvgNumDownvotes,
        AVG(NumComments) AS AvgNumComments,
        AVG(NumDuplicates) AS AvgNumDuplicates
    FROM cte_numeric
    GROUP BY PostTypeId, PostStatus, OwnerDisplayName
)
SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.Title,
    p.Body,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ViewCount,
    p.Score,
    p.PostStatus,
    p.OwnerDisplayName,
    p.DaysSinceCreation,
    p.DaysUntilClosed,
    p.DaysUntilCommunityOwned,
    p.NumClosureEvents,
    p.NumUpvotes,
    p.NumDownvotes,
    p.NumComments,
    p.NumDuplicates,
    a.NumPosts,
    a.AvgDaysSinceCreation,
    a.AvgDaysUntilClosed,
    a.AvgDaysUntilCommunityOwned,
    a.AvgNumClosureEvents,
    a.AvgNumUpvotes,
    a.AvgNumDownvotes,
    a.AvgNumComments,
    a.AvgNumDuplicates
FROM cte_numeric p
LEFT JOIN agg a ON p.PostTypeId = a.PostTypeId AND p.PostStatus = a.PostStatus AND p.OwnerDisplayName = a.OwnerDisplayName
ORDER BY p.Id;