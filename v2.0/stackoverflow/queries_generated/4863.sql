-- {"query": "4863.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 876} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn_user_posts,
        COUNT(c.Id) OVER (PARTITION BY p.Id) as comment_count_post
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.Score > 0
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseVoteCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 19 THEN 1 ELSE NULL END) AS ProtectionCount
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyGiven,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostCreationDate,
    rp.PostScore,
    rp.AnswerCount,
    rp.comment_count_post,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    phs.LastTitleEditDate,
    phs.LastBodyEditDate,
    phs.CloseVoteCount,
    phs.ProtectionCount,
    uvs.UpVoteCount,
    uvs.DownVoteCount,
    uvs.TotalBountyGiven,
    uvs.LastVoteDate,
    CASE
        WHEN rp.PostScore > 1000 AND rp.AnswerCount > 10 THEN 'Highly Rated & Answered'
        WHEN rp.PostScore BETWEEN 100 AND 1000 AND rp.AnswerCount BETWEEN 2 AND 10 THEN 'Moderately Rated & Answered'
        WHEN rp.PostScore < 100 AND rp.AnswerCount < 2 THEN 'Low Engagement'
        ELSE 'Other'
    END AS EngagementCategory,
    CASE
        WHEN uvs.LastVoteDate > rp.PostCreationDate + INTERVAL '1 year' THEN 'Stale Voting'
        WHEN uvs.LastVoteDate IS NULL THEN 'No Voting Activity'
        ELSE 'Recent Voting'
    END AS VotingRecency,
    COALESCE(rp.OwnerReputation, 0) AS EffectiveReputation
FROM RankedPosts rp
FULL OUTER JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN UserVoteStats uvs ON rp.OwnerUserId = uvs.UserId
WHERE rp.rn_user_posts <= 5 OR rp.OwnerUserId IS NULL
ORDER BY rp.PostScore DESC, rp.PostCreationDate ASC
LIMIT 100;
