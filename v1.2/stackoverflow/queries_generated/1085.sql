-- {"query": "1085.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1962} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CAST(t.TagName AS varchar(500)) AS FullPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
    UNION ALL
    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        CONCAT(parent.FullPath, ' > ', child.TagName),
        parent.Level + 1
    FROM Tags child
    INNER JOIN RecursiveTagHierarchy parent ON child.WikiPostId = parent.ExcerptPostId
    WHERE child.IsModeratorOnly = 0 AND parent.Level < 3
),
PostVoteAggregates AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) AS TotalBounty,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreView,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS PostsByUser
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) FILTER (WHERE b.TagBased = 1) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostCommentsSummary AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(LENGTH(c.Text)) AS MaxCommentLength,
        MIN(c.CreationDate) AS FirstCommentDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
DetailedPosts AS (
    SELECT
        pva.Id AS PostId,
        pva.PostTypeId,
        pva.OwnerUserId,
        COALESCE(u.DisplayName, pva.OwnerUserId::varchar) AS OwnerName,
        pva.Title,
        pva.CreationDate,
        pva.Score,
        pva.ViewCount,
        pva.UpVotes,
        pva.DownVotes,
        pva.TotalBounty,
        pva.RankByScoreView,
        pva.PostsByUser,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.TagBasedBadges,
        pcs.CommentCount,
        pcs.AvgCommentScore,
        pcs.MaxCommentLength,
        pcs.FirstCommentDate,
        pcs.LastCommentDate,
        rt.FullPath AS TagHierarchy,
        CASE 
            WHEN pva.Score < 0 THEN 'Negative'
            WHEN pva.Score BETWEEN 0 AND 5 THEN 'Low'
            WHEN pva.Score BETWEEN 6 AND 20 THEN 'Medium'
            ELSE 'High'
        END AS ScoreCategory,
        CASE WHEN pva.TotalBounty > 0 THEN TRUE ELSE FALSE END AS HasBounty,
        COALESCE(clt.Name, 'No Close Reason') AS CloseReason,
        COALESCE(pl.LinkTypeId, 0) AS LinkTypeId,
        COALESCE(lt.Name, 'No Link') AS LinkTypeName
    FROM PostVoteAggregates pva
    LEFT JOIN Users u ON u.Id = pva.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = pva.OwnerUserId
    LEFT JOIN PostCommentsSummary pcs ON pcs.PostId = pva.Id
    LEFT JOIN Posts p ON p.Id = pva.Id
    LEFT JOIN PostHistory ph ON ph.PostId = pva.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN CloseReasonTypes clt ON clt.Id = CAST(ph.Comment AS smallint)
    LEFT JOIN PostLinks pl ON pl.PostId = pva.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    LEFT JOIN RecursiveTagHierarchy rt ON rt.ExcerptPostId = p.Id OR rt.WikiPostId = p.Id
    WHERE pva.RankByScoreView <= 500
),
RecentActivityWindow AS (
    SELECT
        p.Id AS PostId,
        p.LastActivityDate,
        LEAD(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS NextLastActivity,
        LAG(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS PrevLastActivity
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
CorrelatedActivity AS (
    SELECT
        da.PostId,
        da.OwnerUserId,
        da.OwnerName,
        da.Title,
        da.Score,
        da.ViewCount,
        da.UpVotes,
        da.DownVotes,
        da.TotalBounty,
        da.ScoreCategory,
        da.HasBounty,
        da.CloseReason,
        da.LinkTypeId,
        da.LinkTypeName,
        da.GoldBadges,
        da.SilverBadges,
        da.BronzeBadges,
        da.TagBasedBadges,
        da.CommentCount,
        da.AvgCommentScore,
        da.MaxCommentLength,
        da.FirstCommentDate,
        da.LastCommentDate,
        da.TagHierarchy,
        DATEDIFF('day', u.CreationDate, da.CreationDate) AS DaysSinceUserCreation,
        CASE
            WHEN EXISTS (
                SELECT 1 FROM Votes v2 
                WHERE v2.PostId = da.PostId AND v2.VoteTypeId = 4 -- Offensive votes
                AND v2.CreationDate > da.CreationDate
            ) THEN 'Yes' ELSE 'No' 
        END AS HasLaterOffensiveVote,
        COALESCE(ra.NextLastActivity, ra.PrevLastActivity) AS AdjacentActivityDate
    FROM DetailedPosts da
    LEFT JOIN Users u ON u.Id = da.OwnerUserId
    LEFT JOIN RecentActivityWindow ra ON ra.PostId = da.PostId
    WHERE da.ScoreCategory IN ('High', 'Medium') 
      AND da.PostTypeId = 1
      AND (da.TagHierarchy LIKE '%sql%' OR da.TagHierarchy LIKE '%performance%')
)
SELECT
    ca.PostId,
    ca.Title,
    ca.OwnerName,
    ca.Score,
    ca.ViewCount,
    ca.UpVotes,
    ca.DownVotes,
    ca.TotalBounty,
    ca.ScoreCategory,
    ca.HasBounty,
    ca.CloseReason,
    ca.LinkTypeName,
    ca.GoldBadges,
    ca.SilverBadges,
    ca.BronzeBadges,
    ca.TagBasedBadges,
    ca.CommentCount,
    ROUND(ca.AvgCommentScore, 2) AS AvgCommentScore,
    ca.MaxCommentLength,
    ca.FirstCommentDate,
    ca.LastCommentDate,
    ca.TagHierarchy,
    ca.DaysSinceUserCreation,
    ca.HasLaterOffensiveVote,
    ca.AdjacentActivityDate,
    -- Complex string calculation and null handling
    CASE 
        WHEN ca.Title IS NULL THEN '[No Title]'
        WHEN POSITION('?' IN ca.Title) > 0 THEN CONCAT('Q: ', LEFT(ca.Title, POSITION('?' IN ca.Title)-1), '...')
        ELSE ca.Title
    END AS QuestionSnippet,
    -- Nested subquery with exists and not exists
    EXISTS (
        SELECT 1 FROM Comments c 
        WHERE c.PostId = ca.PostId 
          AND (c.Text ILIKE '%help%' OR c.Text ILIKE '%sql%') 
          AND c.Score > 0
    ) AS HasHelpfulComments,
    NOT EXISTS (
        SELECT 1 FROM PostLinks pl2 
        WHERE pl2.PostId = ca.PostId AND pl2.LinkTypeId = 3 -- Duplicate link
    ) AS IsOriginalQuestion
FROM CorrelatedActivity ca
ORDER BY ca.Score DESC, ca.ViewCount DESC
LIMIT 100;
