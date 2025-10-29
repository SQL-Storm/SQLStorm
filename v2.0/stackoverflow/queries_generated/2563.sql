-- {"query": "2563.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1186} 

WITH RecursiveTagHierarchy AS (
    SELECT
        Id,
        TagName,
        WikiPostId,
        0 AS Depth,
        CAST(TagName AS VARCHAR(1000)) AS Path
    FROM Tags
    WHERE Id IS NOT NULL
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.WikiPostId,
        r.Depth + 1,
        r.Path || ' > ' || t.TagName
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy r ON t.ExcerptPostId = r.WikiPostId
    WHERE r.Depth < 3
), 
UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(b.Id) AS TotalBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(vt.Weight),0) AS VoteWeightSum
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY u.Id, u.DisplayName
), 
PostScoresWithRank AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostNumber
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
ClosedQuestionsWithReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        ph.CreationDate AS ClosedAt
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
HighEngagementPosts AS (
    SELECT 
        p.Id,
        p.Title,
        COALESCE(p.ViewCount, 0) AS Views,
        COALESCE(p.Score, 0) AS Score,
        COALESCE(p.FavoriteCount, 0) AS Favorites,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCount
    FROM Posts p
    WHERE p.PostTypeId = 1
), 
UserVoteAgg AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(*) AS TotalVotes
    FROM Votes v
    GROUP BY v.PostId
),
TopLinkedPosts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        COUNT(*) AS LinkCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId IN (1,3) -- Linked or Duplicate
    GROUP BY pl.PostId, pl.RelatedPostId
    HAVING COUNT(*) > 1
)

SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.TotalBadges,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.VoteWeightSum,
    ps.Title AS TopQuestionTitle,
    ps.Score AS TopQuestionScore,
    cqr.CloseReason,
    cqr.ClosedAt,
    he.Views,
    he.Favorites,
    he.CommentCount,
    uv.UpVotes,
    uv.DownVotes,
    uv.TotalVotes,
    STRING_AGG(DISTINCT rth.Path, ' | ') FILTER (WHERE rth.Depth = 1) AS UserTagHierarchy,
    CASE 
        WHEN ua.QuestionsAsked = 0 THEN 'No questions asked'
        WHEN ua.AnswersGiven = 0 THEN 'No answers given'
        ELSE 'Active Q&A participant'
    END AS UserEngagementStatus,
    pl.PostId AS HighlyLinkedPostId,
    pl.RelatedPostId AS HighlyLinkedRelatedPostId,
    pl.LinkCount AS LinkFrequency
FROM UserActivitySummary ua
LEFT JOIN PostScoresWithRank ps ON ps.OwnerUserId = ua.UserId AND ps.ScoreRank = 1 AND ps.PostTypeId = 1
LEFT JOIN ClosedQuestionsWithReasons cqr ON cqr.PostId = ps.Id
LEFT JOIN HighEngagementPosts he ON he.Id = ps.Id
LEFT JOIN UserVoteAgg uv ON uv.PostId = ps.Id
LEFT JOIN RecursiveTagHierarchy rth ON rth.WikiPostId = (
    SELECT p.WikiPostId FROM Tags p WHERE p.Id = rth.Id LIMIT 1
)
LEFT JOIN LATERAL (
    SELECT * FROM TopLinkedPosts pl WHERE pl.PostId = ps.Id LIMIT 1
) pl ON TRUE
WHERE ua.TotalBadges > 0
ORDER BY ua.VoteWeightSum DESC NULLS LAST
LIMIT 50;
