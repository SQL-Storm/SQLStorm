-- {"query": "4999.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1354} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostContributions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        STRING_SPLIT(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ') AS PostTags
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Questions only
),
TagContributionSummary AS (
    SELECT
        pc.PostId,
        pc.OwnerUserId,
        pc.OwnerDisplayName,
        pc.CreationDate,
        pc.Score,
        pc.AnswerCount,
        pc.CommentCount,
        pc.FavoriteCount,
        pc.IsClosed,
        pc.IsCommunityOwned,
        pt.TagName,
        ROW_NUMBER() OVER(PARTITION BY pc.PostId, pt.TagName ORDER BY pc.CreationDate DESC) as rn_tag
    FROM PostContributions pc
    CROSS APPLY pc.PostTags pt
    WHERE pt.TagName IS NOT NULL AND LEN(pt.TagName) > 0
),
TopEditorsPerPost AS (
    SELECT
        rpe.PostId,
        rpe.UserId AS EditorUserId,
        rpe.EditorDisplayName,
        rpe.EditDate
    FROM RankedPostEdits rpe
    WHERE rpe.rn <= 3
),
PostVoteCounts AS (
    SELECT
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN VoteTypeId = 5 THEN 1 END) AS FavoriteVotes,
        COUNT(CASE WHEN VoteTypeId = 8 THEN 1 END) AS BountyStartVotes
    FROM Votes
    WHERE VoteTypeId IN (2, 3, 5, 8)
    GROUP BY PostId
)
SELECT
    pc.PostId,
    pc.OwnerDisplayName,
    pc.CreationDate,
    pc.Score,
    pc.AnswerCount,
    pc.CommentCount,
    pc.FavoriteCount,
    pc.IsClosed,
    pc.IsCommunityOwned,
    pc.TagName,
    COALESCE(pvc.UpVotes, 0) AS TotalUpVotes,
    COALESCE(pvc.DownVotes, 0) AS TotalDownVotes,
    COALESCE(pvc.FavoriteVotes, 0) AS TotalFavoriteVotes,
    COALESCE(pvc.BountyStartVotes, 0) AS TotalBountyStartVotes,
    CASE
        WHEN tepp.EditorUserId IS NOT NULL THEN 'Edited'
        ELSE 'Not Edited'
    END AS EditStatus,
    tepp.EditorDisplayName AS LatestEditor,
    DATEDIFF(day, pc.CreationDate, GETDATE()) AS DaysSinceCreation,
    LEN(pc.OwnerDisplayName) AS OwnerNameLength,
    REPLACE(pc.OwnerDisplayName, ' ', '_') AS OwnerNameWithUnderscores,
    CASE
        WHEN pc.Score > 1000 THEN 'HighScore'
        WHEN pc.Score BETWEEN 100 AND 1000 THEN 'MediumScore'
        ELSE 'LowScore'
    END AS ScoreCategory
FROM TagContributionSummary pc
LEFT JOIN PostVoteCounts pvc ON pc.PostId = pvc.PostId
LEFT JOIN TopEditorsPerPost tepp ON pc.PostId = tepp.PostId AND tepp.rn_tag = 1 -- Join with the top editor for this post
WHERE pc.rn_tag = 1 -- Get only one entry per post for tag analysis
UNION
SELECT
    NULL, -- Placeholder for PostId
    NULL, -- Placeholder for OwnerDisplayName
    MIN(pc.CreationDate) AS EarliestCreationDate,
    AVG(pc.Score) AS AverageScore,
    SUM(pc.AnswerCount) AS TotalAnswers,
    SUM(pc.CommentCount) AS TotalComments,
    SUM(pc.FavoriteCount) AS TotalFavorites,
    SUM(pc.IsClosed) AS TotalClosedPosts,
    SUM(pc.IsCommunityOwned) AS TotalCommunityOwnedPosts,
    NULL, -- Placeholder for TagName
    SUM(COALESCE(pvc.UpVotes, 0)) AS TotalUpVotes,
    SUM(COALESCE(pvc.DownVotes, 0)) AS TotalDownVotes,
    SUM(COALESCE(pvc.FavoriteVotes, 0)) AS TotalFavoriteVotes,
    SUM(COALESCE(pvc.BountyStartVotes, 0)) AS TotalBountyStartVotes,
    NULL, -- Placeholder for EditStatus
    NULL, -- Placeholder for LatestEditor
    AVG(DATEDIFF(day, pc.CreationDate, GETDATE())) AS AverageDaysSinceCreation,
    AVG(LEN(pc.OwnerDisplayName)) AS AverageOwnerNameLength,
    NULL, -- Placeholder for OwnerNameWithUnderscores
    NULL -- Placeholder for ScoreCategory
FROM TagContributionSummary pc
LEFT JOIN PostVoteCounts pvc ON pc.PostId = pvc.PostId
WHERE pc.rn_tag = 1;