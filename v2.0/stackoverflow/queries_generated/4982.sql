-- {"query": "4982.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1215} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserReputationChanges AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        LAG(u.Reputation, 1, u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.CreationDate) AS PreviousReputation,
        u.CreationDate AS UserCreationDate
    FROM Users u
),
PostScoreEvolution AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        LAG(p.Score, 1, p.Score) OVER (PARTITION BY p.Id ORDER BY p.LastActivityDate) AS PreviousScore,
        RANK() OVER (PARTITION BY p.Id ORDER BY p.Score DESC) AS ScoreRankForPost
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
RecentActivity AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS DistinctEditorsInLastMonth,
        MAX(ph.CreationDate) AS LatestEditDate
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATE('now', '-1 month')
    AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId
),
CommentActivity AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountOnPost,
        AVG(c.Score) AS AverageCommentScore
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    COALESCE(pt.Name, 'Unknown Post Type') AS QuestionPostType,
    p.Score AS QuestionScore,
    p.AnswerCount AS QuestionAnswerCount,
    p.FavoriteCount AS QuestionFavoriteCount,
    p.CreationDate AS QuestionCreationDate,
    u.DisplayName AS QuestionOwnerDisplayName,
    u.Reputation AS QuestionOwnerReputation,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS QuestionStatus,
    COALESCE(pse.PreviousScore, 0) AS PreviousQuestionScore,
    CASE
        WHEN pse.ScoreRankForPost = 1 THEN 'TopScoring'
        ELSE 'NotTopScoring'
    END AS ScoreRanking,
    COALESCE(ra.DistinctEditorsInLastMonth, 0) AS EditorsLastMonth,
    ca.CommentCountOnPost,
    ca.AverageCommentScore,
    CASE
        WHEN rpe.rn <= 3 THEN 'FrequentEditor'
        ELSE 'InfrequentEditor'
    END AS EditingFrequency,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount,
    MAX(CASE WHEN p.OwnerUserId = v.UserId THEN 1 ELSE 0 END) AS OwnerVotedUp,
    COALESCE(COUNT(DISTINCT b.Id), 0) AS BadgeCountForOwner
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostScoreEvolution pse ON p.Id = pse.PostId AND pse.ScoreRankForPost = 1
LEFT JOIN RecentActivity ra ON p.Id = ra.PostId
LEFT JOIN CommentActivity ca ON p.Id = ca.PostId
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2 -- Upvotes
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE p.PostTypeId = 1 -- Focus on Questions for this benchmark
AND p.CreationDate >= '2023-01-01' -- Consider recent questions
GROUP BY
    p.Id,
    p.Title,
    p.PostTypeId,
    pt.Name,
    p.Score,
    p.AnswerCount,
    p.FavoriteCount,
    p.CreationDate,
    u.DisplayName,
    u.Reputation,
    QuestionStatus,
    pse.PreviousScore,
    pse.ScoreRankForPost,
    ra.DistinctEditorsInLastMonth,
    ca.CommentCountOnPost,
    ca.AverageCommentScore,
    rpe.rn,
    p.OwnerUserId,
    v.UserId
HAVING COUNT(DISTINCT b.Id) > 0 OR ca.CommentCountOnPost > 5 -- Filter for posts with badges or significant comments
ORDER BY p.CreationDate DESC
LIMIT 100;
