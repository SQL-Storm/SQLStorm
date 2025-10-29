WITH RECURSIVE RecursivePostHierarchy AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        0 AS Level,
        CAST(p.Id AS varchar) AS PathIds
    FROM Posts p
    WHERE p.ParentId IS NULL

    UNION ALL

    SELECT
        c.Id,
        c.PostTypeId,
        c.OwnerUserId,
        c.AcceptedAnswerId,
        c.ParentId,
        c.CreationDate,
        c.Score,
        rh.Level + 1,
        rh.PathIds || '>' || CAST(c.Id AS varchar)
    FROM Posts c
    JOIN RecursivePostHierarchy rh ON c.ParentId = rh.Id
    WHERE rh.Level < 5
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        b.Class,
        count(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > CAST('2024-10-01' AS date) - INTERVAL '365' DAY
    GROUP BY b.UserId, b.Class
),
LatestCommentPerPost AS (
    SELECT
        c.PostId,
        c.Id AS CommentId,
        c.UserId AS CommentUserId,
        c.CreationDate AS CommentDate,
        c.Text AS CommentText,
        row_number() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC NULLS LAST, c.CreationDate DESC) AS rn
    FROM Comments c
    WHERE c.Text IS NOT NULL
),
PostLinkCounts AS (
    SELECT
        pl.PostId,
        count(case when pl.LinkTypeId = 1 then 1 end) AS LinkedCount,
        count(case when pl.LinkTypeId = 3 then 1 end) AS DuplicateCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
PostVotesSummary AS (
    SELECT
        v.PostId,
        count(case when v.VoteTypeId = 2 then 1 end) AS UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) AS DownVotes,
        count(case when v.VoteTypeId = 5 then 1 end) AS Favorites,
        max(v.BountyAmount) AS MaxBounty,
        count(*) AS TotalVotes
    FROM Votes v
    GROUP BY v.PostId
),
CloseReasonSummary AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        min(ph.CreationDate) AS FirstCloseDate
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS integer) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserActivityRanks AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        rank() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        dense_rank() OVER (PARTITION BY date_trunc('year', u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRepRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
ComplexPostScore AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        coalesce(pv.UpVotes,0) - coalesce(pv.DownVotes,0) AS NetVotes,
        coalesce(plc.LinkedCount,0) AS LinkedPosts,
        coalesce(plc.DuplicateCount,0) AS DuplicatePosts,
        coalesce(ubg.GoldCount,0) AS GoldBadges,
        coalesce(ubg.SilverCount,0) AS SilverBadges,
        coalesce(ubg.BronzeCount,0) AS BronzeBadges,
        row_number() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS PostRank,
        LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PrevScore,
        CASE 
            WHEN p.Score > 0 THEN power(p.Score, 1.5) + coalesce(pv.UpVotes,0)*2 - coalesce(pv.DownVotes,0)*3 + coalesce(plc.LinkedCount,0)*1.5
            ELSE p.Score * -1 + coalesce(pv.DownVotes,0)*2
        END AS WeightedScoreEstimate,
        (
          SELECT string_agg(tn, ',' ORDER BY tn)
          FROM (
            SELECT DISTINCT substring(t.TagName FROM 1 FOR 3) AS tn
            FROM (
              SELECT unnest(string_to_array(trim(BOTH '<>' FROM coalesce(p.Tags, '')), '><')) AS TagName
            ) t
          ) s
        ) AS ShortTagList
    FROM Posts p
    LEFT JOIN PostVotesSummary pv ON pv.PostId = p.Id
    LEFT JOIN PostLinkCounts plc ON plc.PostId = p.Id
    LEFT JOIN (
        SELECT
            UserId,
            sum(case when Class = 1 then BadgeCount else 0 end) AS GoldCount,
            sum(case when Class = 2 then BadgeCount else 0 end) AS SilverCount,
            sum(case when Class = 3 then BadgeCount else 0 end) AS BronzeCount
        FROM UserBadgeStats
        GROUP BY UserId
    ) ubg ON ubg.UserId = p.OwnerUserId
    GROUP BY p.Id, p.PostTypeId, p.Title, p.Tags, p.Score, pv.UpVotes, pv.DownVotes, plc.LinkedCount, plc.DuplicateCount, ubg.GoldCount, ubg.SilverCount, ubg.BronzeCount
)
SELECT
    cps.Id AS PostId,
    cps.PostTypeId,
    u.DisplayName AS OwnerUser,
    cps.Title,
    cps.Score,
    cps.NetVotes,
    cps.WeightedScoreEstimate,
    cps.LinkedPosts,
    cps.DuplicatePosts,
    cps.GoldBadges,
    cps.SilverBadges,
    cps.BronzeBadges,
    cps.PostRank,
    cps.PrevScore,
    lcp.CommentText AS LatestTopComment,
    crs.CloseReason,
    crs.FirstCloseDate,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.RepRank,
    ua.YearlyRepRank,
    CASE
        WHEN cps.PostRank <= 10 THEN 'Top10'
        WHEN cps.PostRank <= 100 THEN 'Top100'
        ELSE 'Other'
    END AS PostRankCategory,
    cps.ShortTagList
FROM ComplexPostScore cps
LEFT JOIN Users u ON u.Id = (
    SELECT p.OwnerUserId FROM Posts p WHERE p.Id = cps.Id
)
LEFT JOIN UserActivityRanks ua ON ua.UserId = u.Id
LEFT JOIN LatestCommentPerPost lcp ON lcp.PostId = cps.Id AND lcp.rn = 1
LEFT JOIN CloseReasonSummary crs ON crs.PostId = cps.Id
WHERE cps.PostTypeId IN (1, 2)
  AND (cps.Score > 10 OR cps.GoldBadges > 0)
ORDER BY cps.WeightedScoreEstimate DESC NULLS LAST
LIMIT 50;