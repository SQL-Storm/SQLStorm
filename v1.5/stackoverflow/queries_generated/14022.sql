-- {"query": "14022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 53705, "output_tokens": 24591} 
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
            DATEDIFF(DAY, p.CreationDate, p.ClosedDate),
            DATEDIFF(DAY, p.CreationDate, p.CommunityOwnedDate),
            DATEDIFF(DAY, p.CreationDate, CURRENT_TIMESTAMP)
        ) AS DaysSinceCreation,
        COALESCE(
            DATEDIFF(DAY, p.CreationDate, p.ClosedDate),
            0
        ) AS DaysUntilClosed,
        COALESCE(
            DATEDIFF(DAY, p.CreationDate, p.CommunityOwnedDate),
            0
        ) AS DaysUntilCommunityOwned,
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
    FROM cte
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
FROM cte p
LEFT JOIN agg a ON p.PostTypeId = a.PostTypeId AND p.PostStatus = a.PostStatus AND p.OwnerDisplayName = a.OwnerDisplayName
ORDER BY p.Id;