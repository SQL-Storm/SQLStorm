WITH CTE AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        CASE
            WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
            ELSE (
                SELECT array_agg(tag) FROM (
                    SELECT trim(both '<>' FROM unnest(string_to_array(p.Tags, '><'))) AS tag
                ) t WHERE tag <> ''
            )
        END AS Tags
    FROM Posts p
),
VoteCounts AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId IN (2, 5) THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN VoteTypeId = 4 THEN 1 ELSE 0 END) AS OffensiveVotes
    FROM Votes
    GROUP BY PostId
),
CommentCounts AS (
    SELECT
        PostId,
        COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
),
PostHistoryCounts AS (
    SELECT
        PostId,
        SUM(CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosureCount,
        SUM(CASE WHEN PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        SUM(CASE WHEN PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS DeletionCount
    FROM PostHistory
    GROUP BY PostId
)
SELECT
    CTE.PostId,
    CTE.OwnerUserId,
    CTE.CreationDate,
    CTE.LastActivityDate,
    CTE.Score,
    CTE.ViewCount,
    CTE.AnswerCount,
    CTE.CommentCount,
    CTE.FavoriteCount,
    CTE.PostType,
    CTE.PostStatus,
    CTE.Tags,
    COALESCE(VoteCounts.UpVotes, 0) AS UpVotes,
    COALESCE(VoteCounts.DownVotes, 0) AS DownVotes,
    COALESCE(VoteCounts.OffensiveVotes, 0) AS OffensiveVotes,
    COALESCE(CommentCounts.CommentCount, 0) AS CommentCount,
    COALESCE(PostHistoryCounts.EditCount, 0) AS EditCount,
    COALESCE(PostHistoryCounts.ClosureCount, 0) AS ClosureCount,
    COALESCE(PostHistoryCounts.ReopenCount, 0) AS ReopenCount,
    COALESCE(PostHistoryCounts.DeletionCount, 0) AS DeletionCount
FROM CTE
LEFT JOIN VoteCounts ON CTE.PostId = VoteCounts.PostId
LEFT JOIN CommentCounts ON CTE.PostId = CommentCounts.PostId
LEFT JOIN PostHistoryCounts ON CTE.PostId = PostHistoryCounts.PostId;