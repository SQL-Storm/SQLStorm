-- {"query": "2960.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1551} 

WITH RecursivePostTrees AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        1 AS Depth,
        ARRAY[p.Id] AS PathIds
    FROM Posts p
    WHERE p.ParentId IS NULL

    UNION ALL

    SELECT
        child.Id,
        child.PostTypeId,
        child.ParentId,
        rpt.Depth + 1,
        rpt.PathIds || child.Id
    FROM Posts child
    JOIN RecursivePostTrees rpt ON rpt.Id = child.ParentId
    WHERE NOT child.Id = ANY(rpt.PathIds)
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT DATE(b.Date)) AS BadgeDays
    FROM Badges b
    GROUP BY b.UserId
),
PostVoteSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteVotes,
        MAX(v.BountyAmount) FILTER (WHERE vt.Name IN ('BountyStart','BountyClose')) AS MaxBounty
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
LatestPostHistory AS (
    SELECT ph.PostId,
           ph.PostHistoryTypeId,
           ph.CreationDate,
           ph.UserId,
           ph.UserDisplayName,
           ph.Comment,
           ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
),
CorrelatedCloseReasonCount AS (
    SELECT
        p.Id AS QuestionId,
        (
            SELECT COUNT(1)
            FROM PostHistory ph
            WHERE ph.PostId = p.Id
              AND ph.PostHistoryTypeId = 10
              AND ph.Comment::int = crt.Id
        ) AS CloseReasonCount,
        crt.Name AS CloseReasonName
    FROM Posts p
    CROSS JOIN CloseReasonTypes crt
    WHERE p.PostTypeId = 1 -- Only questions
),
TagSplit AS (
    SELECT
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, char_length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
),
UserActivityWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostWithLinkSummary AS (
    SELECT
        p.Id,
        p.Title,
        p.PostTypeId,
        COUNT(DISTINCT pl.Id) FILTER (WHERE lt.Name = 'Linked') AS LinkedCount,
        COUNT(DISTINCT pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY p.Id, p.Title, p.PostTypeId
),
ComplexPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        pv.UpVotes,
        pv.DownVotes,
        pv.FavoriteVotes,
        pv.MaxBounty,
        COALESCE(rph.PostHistoryTypeId, 0) AS LastPostHistoryType,
        rph.CreationDate AS LastPostHistoryDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.BadgeDays,
        pls.LinkedCount,
        pls.DuplicateCount,
        ROW_NUMBER() OVER (
            PARTITION BY p.PostTypeId
            ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST, pv.UpVotes DESC NULLS LAST
        ) AS PostRank
    FROM Posts p
    LEFT JOIN PostVoteSummary pv ON pv.PostId = p.Id
    LEFT JOIN LatestPostHistory rph ON rph.PostId = p.Id AND rph.rn = 1
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeStats ub ON ub.UserId = p.OwnerUserId
    LEFT JOIN PostWithLinkSummary pls ON pls.Id = p.Id
    WHERE p.PostTypeId IN (1,2) -- Questions or Answers
)
SELECT
    cp.Id AS PostId,
    cp.Title,
    cp.PostTypeId,
    cp.CreationDate,
    cp.Score,
    cp.ViewCount,
    cp.Tags,
    cp.OwnerUserId,
    cp.OwnerDisplayName,
    cp.OwnerReputation,
    cp.GoldBadges,
    cp.SilverBadges,
    cp.BronzeBadges,
    cp.BadgeDays,
    cp.UpVotes,
    cp.DownVotes,
    cp.FavoriteVotes,
    cp.MaxBounty,
    cp.LastPostHistoryType,
    cp.LastPostHistoryDate,
    cp.LinkedCount,
    cp.DuplicateCount,
    ca.CloseReasonName,
    ca.CloseReasonCount,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.BadgeCount,
    rpt.Depth AS ReplyDepth,
    array_length(rpt.PathIds, 1) AS PathLength
FROM ComplexPosts cp
LEFT JOIN CorrelatedCloseReasonCount ca ON ca.QuestionId = CASE WHEN cp.PostTypeId = 1 THEN cp.Id ELSE NULL END
LEFT JOIN UserActivityWindow ua ON ua.Id = cp.OwnerUserId
LEFT JOIN RecursivePostTrees rpt ON rpt.Id = cp.Id
WHERE (COALESCE(cp.UpVotes,0) - COALESCE(cp.DownVotes,0)) > 5
  AND (cp.BadgeDays > 10 OR cp.OwnerReputation > 5000)
  AND (cp.DuplicateCount < 3 OR cp.LinkedCount > 2)
  AND (cp.LastPostHistoryType NOT IN (10,12) OR cp.LastPostHistoryType IS NULL) -- Not closed or deleted recently
ORDER BY cp.Score DESC NULLS LAST, cp.ViewCount DESC NULLS LAST
LIMIT 100;
