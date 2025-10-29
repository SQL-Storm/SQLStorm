-- {"query": "2704.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1672} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        ARRAY[t.TagName] AS TagPath,
        t.Count
    FROM Tags t
    WHERE NOT EXISTS (
        SELECT 1 FROM TagParents tp WHERE tp.ChildTagId = t.Id
    )
    UNION ALL
    SELECT
        tp.ChildTagId,
        t2.TagName,
        rth.TagPath || t2.TagName,
        t2.Count
    FROM RecursiveTagHierarchy rth
    JOIN TagParents tp ON tp.ParentTagId = rth.Id
    JOIN Tags t2 ON t2.Id = tp.ChildTagId
),
RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.CreationDate > NOW() - INTERVAL '1 year'
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TotalBadges,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        COUNT(c.Id) AS CommentsCount,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionScore,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views,
             ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, ubc.TotalBadges
),
PostLinksWithTypes AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        pl.CreationDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
ComplexPosts AS (
    SELECT
        rp.Id,
        rp.PostTypeId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        ua.DisplayName AS OwnerDisplayName,
        ua.Reputation AS OwnerReputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        plwt.LinkTypeName,
        COALESCE(plwt.RelatedPostId, -1) AS RelatedPostId,
        LAG(rp.Score) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) AS PrevPostScore,
        LEAD(rp.Score) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) AS NextPostScore,
        CASE 
            WHEN rp.ViewCount > 1000 THEN 'Popular'
            WHEN rp.ViewCount BETWEEN 100 AND 1000 THEN 'Moderate'
            ELSE 'Less Popular'
        END AS PopularityCategory,
        -- Complex substring + NULL logic example - extract first tag if present
        CASE
            WHEN rp.Tags IS NOT NULL AND LENGTH(rp.Tags) > 2 THEN
                split_part(substring(rp.Tags FROM 2 FOR LENGTH(rp.Tags) - 2), '><', 1)
            ELSE 'NoTag'
        END AS FirstTag
    FROM RankedPosts rp
    LEFT JOIN UserActivity ua ON ua.UserId = rp.OwnerUserId
    LEFT JOIN PostLinksWithTypes plwt ON plwt.PostId = rp.Id
    WHERE rp.UserPostRank = 1
),
AggVotes AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(v.Id) AS TotalVotes,
        AVG(v.BountyAmount::float) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
ClosedPosts AS (
    SELECT
        p.Id,
        p.Title,
        cht.Name AS CloseReason,
        ph.CreationDate AS CloseDate
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    LEFT JOIN CloseReasonTypes cht ON CAST(ph.Comment AS INT) = cht.Id
    WHERE pht.Name = 'Post Closed'
),
UsersWithRecentActivity AS (
    SELECT DISTINCT
        u.Id AS UserId,
        u.DisplayName
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.LastActivityDate > NOW() - INTERVAL '30 days'
)
SELECT
    cp.Id AS PostId,
    cp.Title,
    cp.PopularityCategory,
    cp.FirstTag,
    cp.OwnerDisplayName,
    cp.OwnerReputation,
    cp.GoldBadges,
    cp.SilverBadges,
    cp.BronzeBadges,
    cp.LinkTypeName,
    cp.RelatedPostId,
    av.UpVotes,
    av.DownVotes,
    av.TotalVotes,
    av.AvgBounty,
    cp.PrevPostScore,
    cp.NextPostScore,
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.PostId = cp.Id
       AND (c.Text ILIKE '%thanks%' OR c.Text ILIKE '%helpful%')
    ) AS PositiveCommentsCount,
    EXISTS (
        SELECT 1
        FROM Votes v2
        WHERE v2.PostId = cp.Id
          AND v2.UserId IN (
              SELECT uda.UserId FROM UsersWithRecentActivity uda
          )
        LIMIT 1
    ) AS HasRecentActiveUserVote,
    COALESCE(clp.CloseReason, 'Open') AS CloseReason,
    clp.CloseDate
FROM ComplexPosts cp
LEFT JOIN AggVotes av ON av.PostId = cp.Id
LEFT JOIN ClosedPosts clp ON clp.Id = cp.Id
WHERE 
    -- Complex predicate with NULL logic and arithmetic expression:
    (
        (cp.GoldBadges + cp.SilverBadges + cp.BronzeBadges) > 5
        OR (cp.OwnerReputation > 5000 AND cp.Score > 10)
        OR cp.PopularityCategory = 'Popular'
    )
    AND (
        cp.FirstTag IS NOT NULL
        AND cp.FirstTag <> 'NoTag'
    )
ORDER BY cp.OwnerReputation DESC, av.UpVotes DESC NULLS LAST, cp.CreationDate DESC
LIMIT 100;
