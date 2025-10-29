-- {"query": "4815.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1337} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_score,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS UserReputationRank,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
        SUM(p.AnswerCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswerCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.Id,
        p.Title,
        p.CreationDate,
        u.DisplayName,
        u.Reputation,
        p.PostTypeId,
        p.Score,
        p.AnswerCount
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgeCount,
        MAX(p.CreationDate) AS LastPostCreationDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS CommunityOwnedEdits
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId = 16
    WHERE u.Reputation > 1000
    GROUP BY
        u.Id,
        u.DisplayName
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType,
        CASE
            WHEN lt.Name = 'Duplicate' THEN 'This post is a duplicate of another.'
            WHEN lt.Name = 'Linked' THEN 'This post is linked from another.'
            ELSE 'Other link type.'
        END AS LinkDescription,
        CASE
            WHEN p_related.Score > p_original.Score THEN 'Related post has higher score'
            WHEN p_related.Score < p_original.Score THEN 'Original post has higher score'
            ELSE 'Scores are equal'
        END AS ScoreComparison
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p_original ON pl.PostId = p_original.Id
    JOIN Posts p_related ON pl.RelatedPostId = p_related.Id
    WHERE pl.CreationDate > '2023-01-01'
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostCreationDate,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.CommentCount,
    rp.UserReputationRank,
    CASE
        WHEN rp.PreviousPostScore = 0 AND rp.NextPostScore = 0 THEN 'No Score Context'
        WHEN rp.PreviousPostScore < rp.Score AND rp.NextPostScore < rp.Score THEN 'Score is Locally Maximized'
        WHEN rp.PreviousPostScore > rp.Score AND rp.NextPostScore > rp.Score THEN 'Score is Locally Minimized'
        ELSE 'Score is Intermediate'
    END AS ScoreContext,
    CONCAT(
        'User Rep: ', rp.OwnerReputation,
        ', Post Score: ', rp.Score,
        ', Comments: ', rp.CommentCount
    ) AS PostSummary,
    ue.UpVoteCount,
    ue.DownVoteCount,
    ue.GoldBadgeCount,
    ue.SilverBadgeCount,
    ue.BronzeBadgeCount,
    ue.CommunityOwnedEdits,
    pla.LinkType,
    pla.LinkDescription,
    pla.ScoreComparison,
    CASE
        WHEN rp.PostCreationDate IS NULL THEN 'Unknown Date'
        WHEN rp.PostCreationDate < DATE_SUB(NOW(), INTERVAL 1 YEAR) THEN 'Older than 1 Year'
        ELSE 'Recent'
    END AS PostAgeCategory,
    COALESCE(ue.DisplayName, 'Anonymous/Deleted User') AS UserDisplayNameOrFallback
FROM RankedPosts rp
LEFT JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
LEFT JOIN PostLinkAnalysis pla ON rp.PostId = pla.PostId OR rp.PostId = pla.RelatedPostId
WHERE rp.rn_score <= 10 -- Top 10 posts by score for each post type
  AND rp.OwnerReputation > 500
  AND (pla.LinkType IS NOT NULL OR ue.UpVoteCount > 100)
ORDER BY
    rp.UserReputationRank,
    rp.PostCreationDate DESC;
