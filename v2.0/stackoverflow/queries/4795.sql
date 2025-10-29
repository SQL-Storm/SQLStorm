WITH PostScores AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        pt.Name AS PostTypeName,
        COALESCE(pv.VoteCount, 0) AS TotalVotes,
        COALESCE(pv.UpVotes, 0) AS UpVotes,
        COALESCE(pv.DownVotes, 0) AS DownVotes,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
            COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
            COUNT(*) AS VoteCount
        FROM Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ) pv ON p.Id = pv.PostId
    WHERE p.Score > 100 OR p.FavoriteCount > 50
),
UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RepRank
    FROM Users u
    WHERE u.Reputation > 10000
),
PostInteractionStats AS (
    SELECT
        ps.PostId,
        ps.Title,
        ps.PostTypeName,
        ps.Score,
        ps.TotalVotes,
        ps.UpVotes,
        ps.DownVotes,
        ps.PostStatus,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS HistoryEventCount,
        MAX(c.CreationDate) AS LastCommentDate,
        CAST(DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - ps.CreationDate) AS INTEGER) AS DaysSinceCreation,
        ps.CreationDate,
        ps.OwnerUserId
    FROM PostScores ps
    LEFT JOIN Comments c ON ps.PostId = c.PostId
    LEFT JOIN PostHistory ph ON ps.PostId = ph.PostId
    GROUP BY
        ps.PostId,
        ps.Title,
        ps.PostTypeName,
        ps.Score,
        ps.TotalVotes,
        ps.UpVotes,
        ps.DownVotes,
        ps.PostStatus,
        ps.CreationDate,
        ps.OwnerUserId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        COUNT(DISTINCT pl.PostId) AS PostsWithTag,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p ON (',' || REPLACE(REPLACE(p.Tags, '><', ','), '<', '') || ',') LIKE ('%,' || t.TagName || ',%')
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    WHERE t.Count > 500
    GROUP BY t.TagName, t.Count
)
SELECT
    pis.PostId,
    pis.Title,
    pis.PostTypeName,
    pis.Score,
    pis.TotalVotes,
    pis.UpVotes,
    pis.DownVotes,
    pis.PostStatus,
    pis.CommentCount,
    pis.HistoryEventCount,
    pis.DaysSinceCreation,
    ur.DisplayName AS OwnerDisplayName,
    ur.Reputation AS OwnerReputation,
    ur.RepRank AS OwnerReputationRank,
    CASE
        WHEN ur.UserCreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years') THEN 'Recent User'
        ELSE 'Established User'
    END AS UserTenureStatus,
    COALESCE(tp.TagName, 'No Popular Tag') AS MostFrequentTag,
    COALESCE(tp.TagCount, 0) AS MostFrequentTagCount,
    CASE
        WHEN pis.Score > 1000 AND pis.CommentCount > 50 THEN 'High Engagement'
        WHEN pis.Score < 0 THEN 'Negative Score'
        ELSE 'Standard'
    END AS EngagementCategory,
    REPLACE(pis.Title, '?', '??') AS SanitizedTitle,
    (pis.UpVotes - pis.DownVotes) AS NetVoteScore,
    CAST(pis.HistoryEventCount AS DOUBLE PRECISION) / NULLIF(pis.DaysSinceCreation, 0) AS AvgHistoryEventsPerDay,
    pis.CreationDate,
    ur.UserCreationDate
FROM PostInteractionStats pis
LEFT JOIN UserReputation ur ON pis.OwnerUserId = ur.UserId
LEFT JOIN (
    SELECT TagName, TagCount
    FROM TagPopularity
    WHERE TagRank = 1
) tp ON (pis.Title LIKE ('%' || tp.TagName || '%')) OR (',' || REPLACE(REPLACE(REPLACE(pis.Title, '<', ''), '>', ''), '/', '') || ',') LIKE ('%,' || tp.TagName || ',%')
WHERE pis.DaysSinceCreation > 7

UNION ALL

SELECT
    NULL AS PostId,
    NULL AS Title,
    'Summary' AS PostTypeName,
    AVG(CAST(Score AS DOUBLE PRECISION)) AS Score,
    AVG(CAST(TotalVotes AS DOUBLE PRECISION)) AS TotalVotes,
    AVG(CAST(UpVotes AS DOUBLE PRECISION)) AS UpVotes,
    AVG(CAST(DownVotes AS DOUBLE PRECISION)) AS DownVotes,
    NULL AS PostStatus,
    AVG(CAST(CommentCount AS DOUBLE PRECISION)) AS CommentCount,
    AVG(CAST(HistoryEventCount AS DOUBLE PRECISION)) AS HistoryEventCount,
    AVG(CAST(DaysSinceCreation AS DOUBLE PRECISION)) AS DaysSinceCreation,
    NULL AS OwnerDisplayName,
    NULL AS OwnerReputation,
    NULL AS OwnerReputationRank,
    NULL AS UserTenureStatus,
    NULL AS MostFrequentTag,
    NULL AS MostFrequentTagCount,
    NULL AS EngagementCategory,
    NULL AS SanitizedTitle,
    NULL AS NetVoteScore,
    NULL AS AvgHistoryEventsPerDay,
    NULL AS CreationDate,
    NULL AS UserCreationDate
FROM PostInteractionStats
WHERE DaysSinceCreation > 7;