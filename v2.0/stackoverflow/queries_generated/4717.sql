-- {"query": "4717.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1294} 

WITH RankedUserVotes AS (
    SELECT
        v.UserId,
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        vt.Name AS VoteTypeName,
        ROW_NUMBER() OVER(PARTITION BY v.UserId, v.VoteTypeId ORDER BY v.CreationDate DESC) as rn
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod', 'Favorite')
),
UserVoteSummary AS (
    SELECT
        UserId,
        SUM(CASE WHEN VoteTypeName = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN VoteTypeName = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN VoteTypeName = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteCount,
        COUNT(DISTINCT PostId) AS DistinctVotedPosts
    FROM RankedUserVotes
    WHERE rn <= 100 -- Consider top 100 votes per user per type for performance
    GROUP BY UserId
),
PostVoteAggregates AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteCount,
        SUM(CASE WHEN pht.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN pht.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeleteVoteCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory pht ON p.Id = pht.PostId AND pht.PostHistoryTypeId IN (10, 13)
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(uvs.UpVoteCount, 0) AS TotalUpVotesGiven,
        COALESCE(uvs.DownVoteCount, 0) AS TotalDownVotesGiven,
        COALESCE(uvs.FavoriteCount, 0) AS TotalFavoritesGiven,
        COALESCE(pva.UpVoteCount, 0) AS TotalUpVotesReceived,
        COALESCE(pva.DownVoteCount, 0) AS TotalDownVotesReceived,
        COALESCE(pva.FavoriteCount, 0) AS TotalFavoritesReceived,
        COALESCE(pva.CloseVoteCount, 0) AS TotalCloseVotesOnPosts,
        COALESCE(pva.UndeleteVoteCount, 0) AS TotalUndeleteVotesOnPosts,
        CASE WHEN uvs.DistinctVotedPosts IS NULL THEN 0 ELSE uvs.DistinctVotedPosts END AS DistinctPostsVotedOn,
        CASE
            WHEN u.UpVotes IS NULL OR u.DownVotes IS NULL OR u.UpVotes + u.DownVotes = 0 THEN 0
            ELSE CAST(u.UpVotes AS REAL) / (u.UpVotes + u.DownVotes) * 100
        END AS NetVoteRatio
    FROM Users u
    LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
    LEFT JOIN PostVoteAggregates pva ON u.Id = pva.OwnerUserId
    WHERE u.Reputation > 1000 -- Filter for users with some reputation
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalUpVotesGiven,
    ue.TotalDownVotesGiven,
    ue.TotalFavoritesGiven,
    ue.TotalUpVotesReceived,
    ue.TotalDownVotesReceived,
    ue.TotalFavoritesReceived,
    ue.TotalCloseVotesOnPosts,
    ue.TotalUndeleteVotesOnPosts,
    ue.DistinctPostsVotedOn,
    ue.NetVoteRatio,
    p.Title AS ExamplePostTitle,
    pt.Name AS PostTypeName,
    COALESCE(c.CommentCount, 0) AS CommentCountOnExamplePost,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    CASE
        WHEN p.Tags IS NULL THEN 'No Tags'
        ELSE REPLACE(REPLACE(p.Tags, '<', ''), '>', ' ')
    END AS FormattedTags
FROM UserEngagement ue
LEFT JOIN Posts p ON ue.UserId = p.OwnerUserId AND p.PostTypeId = 1 -- Join to a sample question
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
) c ON p.Id = c.PostId
WHERE p.Id IS NOT NULL -- Ensure we have a valid post to display
ORDER BY ue.Reputation DESC, ue.UserCreationDate ASC
LIMIT 100;
