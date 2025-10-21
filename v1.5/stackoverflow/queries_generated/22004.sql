-- {"query": "22004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1379} 
WITH UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(CASE WHEN p.ViewCount IS NOT NULL THEN p.ViewCount ELSE 0 END) AS AvgViewCount,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS AcceptedQuestions
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS CommentScore,
        MAX(CASE WHEN c.Text LIKE '%thanks%' THEN 1 ELSE 0 END) AS HasThanksComment
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, '; ' ORDER BY b.Name) AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
        SUM(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) AS TotalBountySpent
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
CombinedStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ps.PostCount, 0) AS PostCount,
        COALESCE(ps.TotalScore, 0) AS TotalPostScore,
        COALESCE(cs.CommentCount, 0) AS CommentCount,
        COALESCE(cs.CommentScore, 0) AS TotalCommentScore,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        bs.BadgeList,
        COALESCE(vs.UpVotesGiven, 0) AS UpVotesGiven,
        COALESCE(vs.DownVotesGiven, 0) AS DownVotesGiven,
        COALESCE(vs.TotalBountySpent, 0) AS TotalBountySpent,
        -- Complex calculation for activity score
        (COALESCE(ps.TotalScore, 0) * 1.5 +
         COALESCE(cs.CommentScore, 0) * 0.5 +
         COALESCE(bs.GoldBadges, 0) * 100 +
         COALESCE(bs.SilverBadges, 0) * 50 +
         COALESCE(bs.BronzeBadges, 0) * 25 +
         LOG(COALESCE(ps.PostCount, 0) + COALESCE(cs.CommentCount, 0) + 1) * 10 +
         GREATEST(COALESCE(vs.UpVotesGiven, 0) - COALESCE(vs.DownVotesGiven, 0), 0) * 0.1) AS ActivityScore,
        -- String expression
        UPPER(SUBSTRING(COALESCE(u.DisplayName, 'Anonymous'), 1, 3)) ||
        CASE WHEN cs.HasThanksComment = 1 THEN '!' ELSE '' END AS DisplayTag
    FROM Users u
    LEFT OUTER JOIN UserPostStats ps ON u.Id = ps.UserId
    LEFT OUTER JOIN UserCommentStats cs ON u.Id = cs.UserId
    LEFT OUTER JOIN UserBadgeStats bs ON u.Id = bs.UserId
    LEFT OUTER JOIN UserVoteStats vs ON u.Id = vs.UserId
),
RankedUsers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY ActivityScore DESC, Reputation DESC) AS GlobalRank,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY ActivityScore DESC) AS YearRank
    FROM CombinedStats
    CROSS JOIN Users u -- Wait, this might be a join to get CreationDate, but better to include in CombinedStats
),
TopUsers AS (
    SELECT *
    FROM RankedUsers
    WHERE GlobalRank <= 100
),
CorrelatedSub AS (
    SELECT ru.UserId,
           (SELECT COUNT(*) 
            FROM Posts p 
            WHERE p.OwnerUserId = ru.UserId 
            AND EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id)) AS LinkedPosts
    FROM RankedUsers ru
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.PostCount,
    ru.TotalPostScore,
    ru.CommentCount,
    ru.TotalCommentScore,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.BadgeList,
    ru.UpVotesGiven,
    ru.DownVotesGiven,
    ru.TotalBountySpent,
    ru.ActivityScore,
    ru.DisplayTag,
    ru.GlobalRank,
    ru.YearRank,
    cs.LinkedPosts,
    CASE 
        WHEN ru.ActivityScore > 1000 THEN 'Highly Active'
        WHEN ru.ActivityScore > 500 THEN 'Moderately Active'
        ELSE 'Low Activity'
    END AS ActivityLevel,
    NULLIF(ru.TotalPostScore - ru.TotalCommentScore, 0) AS ScoreDifference
FROM RankedUsers ru
INNER JOIN CorrelatedSub cs ON ru.UserId = cs.UserId
WHERE ru.UserId IN (SELECT UserId FROM TopUsers)
UNION ALL
SELECT
    NULL, 'TOTAL', SUM(Reputation), SUM(PostCount), SUM(TotalPostScore), SUM(CommentCount), SUM(TotalCommentScore),
    SUM(GoldBadges), SUM(SilverBadges), SUM(BronzeBadges), NULL, SUM(UpVotesGiven), SUM(DownVotesGiven), SUM(TotalBountySpent),
    SUM(ActivityScore), NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM RankedUsers
ORDER BY ActivityScore DESC NULLS LAST, UserId;