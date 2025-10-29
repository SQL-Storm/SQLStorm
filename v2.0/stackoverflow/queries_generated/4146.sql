-- {"query": "4146.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1355} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditStats AS (
    SELECT
        pe.PostId,
        COUNT(DISTINCT pe.UserId) AS DistinctEditors,
        AVG(DATEDIFF(minute, LAG(pe.EditDate, 1, pe.EditDate) OVER (PARTITION BY pe.PostId ORDER BY pe.EditDate), pe.EditDate)) AS AvgTimeBetweenEditsMinutes,
        MAX(pe.EditDate) AS LastEditDate
    FROM RankedPostEdits pe
    GROUP BY pe.PostId
),
UserPostContribution AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS PostsOwned,
        SUM(p.Score) AS TotalScoreFromPosts,
        SUM(p.ViewCount) AS TotalViewsOnPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    GROUP BY p.OwnerUserId
),
UserCommentContribution AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(c.Score) AS TotalScoreFromComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteContribution AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
FinalPostDetails AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(pes.DistinctEditors, 0) AS NumberOfDistinctEditors,
        COALESCE(pes.AvgTimeBetweenEditsMinutes, 0) AS AvgMinutesBetweenEdits,
        COALESCE(upc.PostsOwned, 0) AS UserTotalPostsOwned,
        COALESCE(upc.TotalScoreFromPosts, 0) AS UserTotalScoreFromPosts,
        COALESCE(ucc.CommentsMade, 0) AS UserTotalCommentsMade,
        COALESCE(uvc.UpVotesGiven, 0) AS UserTotalUpVotesGiven,
        COALESCE(uvc.DownVotesGiven, 0) AS UserTotalDownVotesGiven,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE 'User Owned' END AS OwnershipStatus,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        CONCAT(
            SUBSTRING(p.Tags, 2, CHARINDEX('><', p.Tags) - 2), -- First tag
            CASE
                WHEN CHARINDEX('><', p.Tags, CHARINDEX('><', p.Tags) + 1) > 0 THEN
                    CONCAT(', ', SUBSTRING(p.Tags, CHARINDEX('><', p.Tags) + 2, CHARINDEX('><', p.Tags, CHARINDEX('><', p.Tags) + 1) - CHARINDEX('><', p.Tags) - 3)) -- Second tag if exists
                ELSE ''
            END
        ) AS PrimaryTags
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostEditStats pes ON p.Id = pes.PostId
    LEFT JOIN UserPostContribution upc ON p.OwnerUserId = upc.OwnerUserId
    LEFT JOIN UserCommentContribution ucc ON p.OwnerUserId = ucc.UserId
    LEFT JOIN UserVoteContribution uvc ON p.OwnerUserId = uvc.UserId
)
SELECT
    fpd.*,
    CASE
        WHEN fpd.Score > 100 AND fpd.AnswerCount > 5 AND fpd.NumberOfDistinctEditors > 3 THEN 'High Engagement Post'
        WHEN fpd.Score < 0 AND fpd.AnswerCount = 0 AND fpd.PostStatus = 'Open' THEN 'Low Performing Post'
        WHEN fpd.OwnershipStatus = 'Community Owned' AND fpd.CreationDate < DATE('now', '-5 years') THEN 'Aged Community Wiki'
        ELSE 'Standard Post'
    END AS PerformanceCategory,
    CASE
        WHEN uvc.DownVotesGiven > uvc.UpVotesGiven * 2 AND uvc.DownVotesGiven > 10 THEN 'High Downvote Ratio'
        ELSE 'Normal Vote Ratio'
    END AS VotePattern
FROM FinalPostDetails fpd
LEFT JOIN UserVoteContribution uvc ON fpd.OwnerUserId = uvc.UserId
WHERE fpd.PostType IN ('Question', 'Answer')
  AND YEAR(fpd.CreationDate) BETWEEN 2020 AND 2023
ORDER BY fpd.Score DESC, fpd.ViewCount DESC
LIMIT 1000;