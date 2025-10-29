-- {"query": "4579.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1599}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RowNumByType,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        CASE
            WHEN p.Tags IS NOT NULL THEN
                REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><', ','), '&lt;', '<')
            ELSE
                NULL
        END AS FormattedTags,
        -- Use standard SQL date diff equivalent: extract(epoch ...) / 86400 for portability is not ideal;
        -- keep DATEDIFF for dialects that support it, but provide an ANSI-like fallback using (CAST...).
        -- Here use DATE_PART day difference for PostAgeInDays when possible:
        CAST(DATE_PART('day', (p.LastActivityDate - p.CreationDate)) AS INTEGER) AS PostAgeInDays
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        COUNT(DISTINCT ph.PostId) AS PostsEdited,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1 ELSE 0 END) AS InitialPostsCreated,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS PostEdits,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users AS u
    JOIN PostHistory AS ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName
),
HighReputationUsers AS (
    SELECT
        Id,
        DisplayName
    FROM Users
    WHERE Reputation > 10000
),
RecentAndPopularQuestions AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        Score,
        ViewCount,
        AnswerCount,
        CreationDate
    FROM Posts
    WHERE PostTypeId = 1
      AND CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months')
      AND Score > 50
      AND ViewCount > 1000
),
PostsWithVotes AS (
    SELECT
        p.Id,
        p.Title,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Posts AS p
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    GROUP BY p.Id, p.Title
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.FormattedTags,
    rp.PostAgeInDays,
    rp.IsClosed,
    rp.AvgScoreByType,
    COALESCE(ua.PostsEdited, 0) AS UserTotalPostsEdited,
    COALESCE(ua.InitialPostsCreated, 0) AS UserInitialPosts,
    COALESCE(ua.PostEdits, 0) AS UserPostEdits,
    CASE
        WHEN hru.Id IS NOT NULL THEN 'High Reputation'
        ELSE 'Standard Reputation'
    END AS UserReputationStatus,
    rpq.Title AS RecentPopularQuestionTitle,
    pvw.VoteCount AS TotalVotesOnPost,
    pvw.UpVoteCount,
    pvw.DownVoteCount,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'Community Owned Post'
        ELSE 'User Owned Post'
    END AS OwnershipType,
    CASE
        WHEN CAST(DATE_PART('hour', (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - rp.PostCreationDate)) AS INTEGER) < 24 THEN 'Recent'
        WHEN CAST(DATE_PART('hour', (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - rp.PostCreationDate)) AS INTEGER) BETWEEN 24 AND 168 THEN 'This Week'
        ELSE 'Older'
    END AS PostRecencyGroup,
    (rp.PostScore * 1.0 / NULLIF(rp.PostViewCount, 0)) AS ScoreToViewRatio,
    rp.AnswerCount,
    rp.CommentCountForPost,
    rp.FavoriteCount
FROM RankedPosts AS rp
LEFT JOIN UserActivity AS ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN HighReputationUsers AS hru ON rp.OwnerUserId = hru.Id
LEFT JOIN RecentAndPopularQuestions AS rpq ON rp.OwnerUserId = rpq.OwnerUserId
LEFT JOIN PostsWithVotes AS pvw ON rp.PostId = pvw.Id
WHERE rp.PostCreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')
  AND rp.PostScore > -5
  AND rp.OwnerDisplayName IS NOT NULL
  AND (rp.FormattedTags IS NULL OR rp.FormattedTags LIKE '%sql%')
  AND rp.PostTypeName <> 'WikiPlaceholder'
GROUP BY
    rp.PostId,
    rp.PostTypeId,
    rp.PostTypeName,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.IsClosed,
    rp.RowNumByType,
    rp.AvgScoreByType,
    rp.CommentCountForPost,
    rp.FormattedTags,
    rp.PostAgeInDays,
    ua.PostsEdited,
    ua.InitialPostsCreated,
    ua.PostEdits,
    hru.Id,
    rpq.Title,
    pvw.VoteCount,
    pvw.UpVoteCount,
    pvw.DownVoteCount
HAVING COUNT(rp.PostId) > 0
ORDER BY rp.PostCreationDate DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;