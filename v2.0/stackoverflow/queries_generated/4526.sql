-- {"query": "4526.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1323} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_creation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_score,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
        p.AnswerCount,
        p.CommentCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN rp.PostTypeId = 1 THEN rp.PostId END) AS QuestionCount,
        COUNT(CASE WHEN rp.PostTypeId = 2 THEN rp.PostId END) AS AnswerCount,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN rp.PostScore ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN rp.PostScore ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN rp.PostTypeId = 1 THEN rp.PostViewCount ELSE NULL END) AS AvgQuestionViews,
        MAX(rp.PostCreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentHighScoringPosts AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.PostScore,
        rp.PostCreationDate,
        ups.DisplayName AS OwnerDisplayName,
        ups.Reputation AS OwnerReputation
    FROM RankedPosts rp
    JOIN UserPostStats ups ON rp.OwnerUserId = ups.UserId
    WHERE rp.rn_score <= 100
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
PostVoteAnalysis AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-365 day')
    GROUP BY p.Id
)
SELECT
    rhsp.PostId,
    rhsp.PostTypeName,
    rhsp.PostScore,
    rhsp.PostCreationDate,
    rhsp.OwnerDisplayName,
    rhsp.OwnerReputation,
    pc.CommentCount,
    COALESCE(pc.TotalCommentScore, 0) AS TotalCommentScore,
    pva.UpVotes,
    pva.DownVotes,
    pva.Favorites,
    CASE
        WHEN rhsp.PostScore > 1000 AND rhsp.OwnerReputation > 50000 THEN 'Highly Esteemed'
        WHEN rhsp.PostScore BETWEEN 500 AND 1000 AND rhsp.OwnerReputation BETWEEN 10000 AND 50000 THEN 'Established Contributor'
        WHEN rhsp.PostScore < 100 THEN 'Nascent Question'
        ELSE 'Standard Question'
    END AS PostStatusCategory,
    CASE
        WHEN (pva.UpVotes - pva.DownVotes) > (pc.CommentCount * 2) THEN 'Vote Heavy'
        WHEN pc.CommentCount > (pva.UpVotes + pva.DownVotes) / 2 THEN 'Comment Heavy'
        ELSE 'Balanced Engagement'
    END AS EngagementStyle,
    CASE
        WHEN rhsp.OwnerReputation IS NULL OR ups_derived.DisplayName IS NULL THEN 'Unknown Owner'
        WHEN rhsp.OwnerReputation < 1000 THEN 'New User'
        WHEN ups_derived.LastPostDate >= DATE('now', '-30 day') THEN 'Active User'
        ELSE 'Lapsed User'
    END AS UserActivityStatus,
    UPPER(SUBSTRING(rhsp.OwnerDisplayName, 1, 1)) || LOWER(SUBSTRING(rhsp.OwnerDisplayName, 2)) AS FormattedDisplayName
FROM RecentHighScoringPosts rhsp
LEFT JOIN PostComments pc ON rhsp.PostId = pc.PostId
LEFT JOIN PostVoteAnalysis pva ON rhsp.PostId = pva.PostId
LEFT JOIN UserPostStats ups_derived ON rhsp.OwnerUserId = ups_derived.UserId
WHERE rhsp.PostScore > 0
ORDER BY rhsp.PostScore DESC, rhsp.PostCreationDate ASC
LIMIT 1000;
