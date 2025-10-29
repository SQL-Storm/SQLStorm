-- {"query": "2161.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2020} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(t.ExcerptPostId, 0) AS ExcerptPostId,
        COALESCE(t.WikiPostId, 0) AS WikiPostId,
        CAST(t.TagName AS VARCHAR(1000)) AS FullHierarchy,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        COALESCE(child.ExcerptPostId, 0),
        COALESCE(child.WikiPostId, 0),
        rh.FullHierarchy || ' > ' || child.TagName,
        Level + 1
    FROM Tags child
    INNER JOIN RecursiveTagHierarchy rh ON child.Id > rh.Id AND child.IsModeratorOnly = 0
    WHERE Level < 3
),
FilteredPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) -- questions and answers
      AND p.CreationDate > NOW() - INTERVAL '2 years'
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '2 years'
    GROUP BY b.UserId, b.Class
),
UserAggregate AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN ubc.BadgeCount ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN ubc.BadgeCount ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN ubc.BadgeCount ELSE 0 END), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.Location, u.Views, u.UpVotes, u.DownVotes
),
PostActivityRanked AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.IsClosed,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostNum
    FROM FilteredPosts p
),
PostWithAcceptedAnswer AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.OwnerUserId AS AcceptedAnswerOwner,
        a.CreationDate AS AcceptedAnswerCreation,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentQty
    FROM Posts p
    LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
    WHERE p.PostTypeId = 1
),
PostHistoryDiffs AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS DistinctHistoryEventCount,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        MIN(ph.CreationDate) AS FirstHistoryEventDate,
        COUNT(*) AS TotalEvents
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostHistoriesWithReasons AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN ph.Comment ELSE NULL END) AS CloseReopenReason,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenVotes
    FROM PostHistory ph
    GROUP BY ph.PostId, ph.PostHistoryTypeId
),
TaggedPosts AS (
    SELECT 
        p.Id,
        p.Tags,
        UNNEST(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ')) AS SingleTag
    FROM Posts p
    WHERE p.Tags IS NOT NULL
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.IsClosed,
    ph.DistinctHistoryEventCount,
    ph.TotalEvents,
    ph.LastHistoryEventDate,
    ph.FirstHistoryEventDate,
    phwr.CloseReopenReason,
    phwr.CloseVotes,
    phwr.ReopenVotes,
    pa.AcceptedAnswerScore,
    pa.AcceptedAnswerOwner,
    pa.AcceptedAnswerCreation,
    pa.CommentQty,
    STRING_AGG(DISTINCT rh.FullHierarchy, ' | ') AS RelatedTagHierarchies,
    -- Complex predicating score growth estimate:
    CASE 
        WHEN p.CreationDate < NOW() - INTERVAL '6 months' THEN 
            ((p.Score::FLOAT / EXTRACT(epoch FROM (NOW() - p.CreationDate))) * 86400 * 30) * 1.5 + u.Reputation * 0.0001
        ELSE 
            (p.Score::FLOAT * 2) + u.Reputation * 0.0005
    END AS ScoreGrowthEstimate,
    -- String expression with NULL logic:
    CASE 
        WHEN u.Location IS NULL OR LENGTH(u.Location) = 0 THEN 'Unknown Location' 
        ELSE LOWER(TRIM(u.Location))
    END || ' - ' || COALESCE(u.DisplayName, 'Anonymous') AS UserLocationDisplayName,
    -- Window function rank on user posts by score:
    RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS UserPostScoreRank,
    -- Correlated scalar subquery for average vote count on user's posts:
    (
        SELECT AVG(COALESCE(vc.VoteCount, 0))
        FROM (
            SELECT v.PostId, COUNT(*) AS VoteCount
            FROM Votes v
            JOIN Posts pp ON pp.Id = v.PostId AND pp.OwnerUserId = u.Id
            GROUP BY v.PostId
        ) vc
    ) AS AvgVotesPerPost,
    -- Set operator example: union questions and answers count per user
    COALESCE(qc.QuestionCount, 0) + COALESCE(ac.AnswerCount, 0) AS TotalQnAs
FROM Users u
LEFT JOIN PostActivityRanked p ON p.OwnerUserId = u.Id AND p.PostRank <= 3
LEFT JOIN PostHistoryDiffs ph ON ph.PostId = p.Id
LEFT JOIN PostHistoriesWithReasons phwr ON phwr.PostId = p.Id
LEFT JOIN PostWithAcceptedAnswer pa ON pa.Id = p.Id
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(REPLACE(REPLACE(p.Tags,'<',''),'>',''), ' '))
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS QuestionCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
) qc ON qc.OwnerUserId = u.Id
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
) ac ON ac.OwnerUserId = u.Id
WHERE u.Reputation > 1000
  AND p.CreationDate > NOW() - INTERVAL '1 year'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, u.Location, u.GoldBadges, u.SilverBadges, u.BronzeBadges,
    p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.IsClosed,
    ph.DistinctHistoryEventCount, ph.TotalEvents, ph.LastHistoryEventDate, ph.FirstHistoryEventDate,
    phwr.CloseReopenReason, phwr.CloseVotes, phwr.ReopenVotes,
    pa.AcceptedAnswerScore, pa.AcceptedAnswerOwner, pa.AcceptedAnswerCreation, pa.CommentQty,
    qc.QuestionCount, ac.AnswerCount
ORDER BY u.Reputation DESC, ScoreGrowthEstimate DESC
LIMIT 50;
