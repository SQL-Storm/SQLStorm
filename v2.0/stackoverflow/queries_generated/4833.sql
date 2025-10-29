-- {"query": "4833.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1370} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        pht.Name AS EditTypeName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditSummary AS (
    SELECT
        rpe.PostId,
        rpe.EditorDisplayName,
        rpe.EditDate,
        rpe.EditTypeName,
        LAG(rpe.EditTypeName, 1, 'No Previous Edit') OVER (PARTITION BY rpe.PostId ORDER BY rpe.EditDate) AS PreviousEditType,
        CASE
            WHEN LEAD(rpe.EditTypeName, 1, 'No Subsequent Edit') OVER (PARTITION BY rpe.PostId ORDER BY rpe.EditDate) = 'No Subsequent Edit' THEN 'Last Edit'
            ELSE 'Not Last Edit'
        END AS IsLastEditFlag
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1 -- Only consider the most recent edit for each post for this part
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostCreationDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(c.Score) AS AverageCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
HighlyRatedUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        upa.TotalPosts,
        uca.TotalComments,
        COALESCE(upa.TotalViews, 0) AS TotalPostViews,
        COALESCE(uca.AverageCommentScore, 0) AS AvgCommentScore,
        CASE
            WHEN u.UpVotes > u.DownVotes * 2 THEN 'High Upvote Ratio'
            WHEN u.DownVotes > u.UpVotes * 2 THEN 'High Downvote Ratio'
            ELSE 'Balanced Votes'
        END AS VoteRatioCategory
    FROM Users u
    LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
    LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
    WHERE u.Reputation > 1000
)
SELECT
    p.Id AS PostId,
    p.Title,
    pt.Name AS PostType,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    pes.EditorDisplayName AS LastEditor,
    pes.EditDate AS LastEditDate,
    pes.EditTypeName AS LastEditType,
    pes.PreviousEditType AS PreviousEditType,
    pes.IsLastEditFlag,
    phr.Comment AS LastPostHistoryComment,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(p.ClosedDate, '1900-01-01') AS EffectiveClosedDate,
    CASE
        WHEN p.OwnerUserId IS NOT NULL AND u.Reputation > 5000 THEN 'Experienced User'
        WHEN p.OwnerUserId IS NOT NULL AND u.Reputation > 1000 THEN 'Intermediate User'
        ELSE 'Novice User'
    END AS UserExperienceLevel,
    CASE
        WHEN INSTR(p.Tags, '<sql>') > 0 THEN 'SQL Tagged'
        WHEN INSTR(p.Tags, '<python>') > 0 THEN 'Python Tagged'
        ELSE 'Other Tagged'
    END AS PrimaryTagCategory,
    hr.Reputation AS OwnerReputation,
    hr.TotalPosts AS OwnerTotalPosts,
    hr.TotalComments AS OwnerTotalComments,
    hr.VoteRatioCategory AS OwnerVoteRatioCategory
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostEditSummary pes ON p.Id = pes.PostId
LEFT JOIN (
    SELECT PostId, Comment, CreationDate
    FROM PostHistory
    WHERE PostHistoryTypeId = 10 -- Post Closed
    ORDER BY CreationDate DESC
    LIMIT 1
) AS ph_closed ON p.Id = ph_closed.PostId
LEFT JOIN (
    SELECT PostId, Comment, CreationDate
    FROM PostHistory
    WHERE PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) -- Various edit types to find a comment
    ORDER BY CreationDate DESC
    LIMIT 1
) AS phr ON p.Id = phr.PostId
LEFT JOIN HighlyRatedUsers hr ON p.OwnerUserId = hr.Id
WHERE p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND p.Score > 10
  AND p.OwnerUserId IS NOT NULL
  AND EXISTS (
      SELECT 1
      FROM Comments c
      WHERE c.PostId = p.Id
      AND c.Score > 5
  )
ORDER BY p.LastActivityDate DESC
LIMIT 100;
