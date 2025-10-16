-- {"query": "810.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1593} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level,
        ARRAY[t.TagName] AS AncestorPath
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.AncestorPath || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.IsModeratorOnly = 0 AND t2.Id <> ALL(r.AncestorPath)
    WHERE r.Level < 3
),
UserBadgeScores AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 2 ELSE 1 END), 0) AS BadgeWeight,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(b.Id) DESC NULLS LAST) AS Rank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostAnalysis AS (
    SELECT
        p.Id,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserPostCount,
        -- Number of comments by distinct users on the post
        (SELECT COUNT(DISTINCT c.UserId)
         FROM Comments c
         WHERE c.PostId = p.Id AND c.UserId IS NOT NULL) AS DistinctCommenters,
        -- Whether the accepted answer was posted by the owner (self-accepted)
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL AND EXISTS (
                SELECT 1 FROM Posts a WHERE a.Id = p.AcceptedAnswerId AND a.OwnerUserId = p.OwnerUserId
            ) THEN 1 ELSE 0
        END AS IsSelfAccepted
    FROM Posts p
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
LinkAggregates AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Linked') AS LinkedCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
),
WindowedVotes AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        vt.Name as VoteTypeName,
        COUNT(*) AS VoteCount,
        RANK() OVER (PARTITION BY v.PostId ORDER BY COUNT(*) DESC) AS VoteRank
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId, v.VoteTypeId, vt.Name
),
PostHistoryAggregates AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,12,14)) AS CloseOrDeletedOrSuggestedEdits,
        MAX(ph.CreationDate) AS LastHistoryEditDate,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors
    FROM PostHistory ph
    GROUP BY ph.PostId
),
ComplexPosts AS (
    SELECT
        pa.*,
        la.LinkedCount,
        la.DuplicateCount,
        COALESCE(wv_up.VoteCount, 0) AS UpVotes,
        COALESCE(wv_down.VoteCount, 0) AS DownVotes,
        phagg.CloseOrDeletedOrSuggestedEdits,
        phagg.LastHistoryEditDate,
        phagg.DistinctEditors,
        -- String manipulation: concatenate top 3 tags or fallback to 'NoTags'
        COALESCE(
            (SELECT STRING_AGG(tag, ', ') FROM (
                SELECT unnest(string_to_array(substring(pa.Tags from 2 for length(pa.Tags)-2), '><')) AS tag
                LIMIT 3
            ) sub), 'NoTags') AS TopTags,
        -- Complex predicate: recent and high engagement post flag
        CASE
            WHEN pa.CreationDate > NOW() - INTERVAL '90 days' AND pa.Score > 10 AND pa.ViewCount > 1000 THEN 1
            ELSE 0
        END AS IsHotPost,
        -- Null logic and coalesce: OwnerDisplayName or fallback to 'Anonymous'
        COALESCE(pa.OwnerName, 'Anonymous') AS FinalOwnerName,
        -- Correlated subquery: count of answers for question posts, else 0
        CASE WHEN pa.PostTypeId = 1 THEN
            (SELECT COUNT(*) FROM Posts ans WHERE ans.ParentId = pa.Id AND ans.PostTypeId = 2)
        ELSE 0 END AS RealAnswerCount
    FROM PostAnalysis pa
    LEFT JOIN LinkAggregates la ON la.PostId = pa.Id
    LEFT JOIN WindowedVotes wv_up ON wv_up.PostId = pa.Id AND wv_up.VoteTypeName = 'UpMod'
    LEFT JOIN WindowedVotes wv_down ON wv_down.PostId = pa.Id AND wv_down.VoteTypeName = 'DownMod'
    LEFT JOIN PostHistoryAggregates phagg ON phagg.PostId = pa.Id
)
SELECT
    cp.Id,
    cp.PostTypeName,
    cp.Title,
    cp.FinalOwnerName,
    cp.Reputation,
    cp.Score,
    cp.ViewCount,
    cp.AnswerCount,
    cp.RealAnswerCount,
    cp.CommentCount,
    cp.FavoriteCount,
    cp.AcceptedAnswerId,
    cp.IsSelfAccepted,
    cp.LinkedCount,
    cp.DuplicateCount,
    cp.UpVotes,
    cp.DownVotes,
    cp.CloseOrDeletedOrSuggestedEdits,
    cp.LastHistoryEditDate,
    cp.DistinctEditors,
    cp.TopTags,
    cp.IsHotPost,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.BadgeWeight,
    ub.Rank AS UserRank
FROM ComplexPosts cp
LEFT JOIN UserBadgeScores ub ON ub.UserId = cp.OwnerUserId
WHERE cp.IsHotPost = 1
ORDER BY cp.Score DESC, cp.ViewCount DESC, ub.Reputation DESC
LIMIT 100;
