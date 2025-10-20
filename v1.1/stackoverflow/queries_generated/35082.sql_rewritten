-- {"query": "35082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 938} 
WITH TopUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, COUNT(p.Id) AS PostCount, SUM(p.Score) AS TotalScore, SUM(p.ViewCount) AS TotalViews
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
      AND p.PostTypeId IN (1,2)
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 50
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class=1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class=2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class=3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT u.Id AS UserId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId=2) AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId=3) AS DownVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId IN (8,9)) AS BountiesGiven,
        COALESCE(SUM(v.BountyAmount),0) AS TotalBountyAmount
    FROM Users u
    LEFT JOIN Votes v ON u.Id=v.UserId
    GROUP BY u.Id
),
UserComments AS (
    SELECT c.UserId, COUNT(*) AS CommentCount, COALESCE(SUM(c.Score),0) AS CommentScore
    FROM Comments c
    GROUP BY c.UserId
),
UserEditHistory AS (
    SELECT ph.UserId, COUNT(*) AS Edits,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditPosts,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (24)) AS SuggestedEdits
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
ActivitySummary AS (
    SELECT
        tu.UserId,
        tu.DisplayName,
        tu.PostCount,
        tu.TotalScore,
        tu.TotalViews,
        COALESCE(b.GoldBadges,0) AS GoldBadges,
        COALESCE(b.SilverBadges,0) AS SilverBadges,
        COALESCE(b.BronzeBadges,0) AS BronzeBadges,
        COALESCE(v.UpVotesGiven,0) AS UpVotesGiven,
        COALESCE(v.DownVotesGiven,0) AS DownVotesGiven,
        COALESCE(v.BountiesGiven,0) AS BountiesGiven,
        COALESCE(v.TotalBountyAmount,0) AS TotalBountyAmount,
        COALESCE(c.CommentCount,0) AS CommentsGiven,
        COALESCE(c.CommentScore,0) AS TotalCommentScore,
        COALESCE(h.Edits,0) AS Edits,
        COALESCE(h.EditPosts,0) AS EditPosts,
        COALESCE(h.SuggestedEdits,0) AS SuggestedEdits
    FROM TopUsers tu
    LEFT JOIN UserBadges b ON tu.UserId = b.UserId
    LEFT JOIN UserVotes v ON tu.UserId = v.UserId
    LEFT JOIN UserComments c ON tu.UserId = c.UserId
    LEFT JOIN UserEditHistory h ON tu.UserId = h.UserId
)
SELECT
    a.UserId,
    a.DisplayName,
    a.PostCount,
    a.TotalScore,
    a.TotalViews,
    a.GoldBadges,
    a.SilverBadges,
    a.BronzeBadges,
    a.UpVotesGiven,
    a.DownVotesGiven,
    a.BountiesGiven,
    a.TotalBountyAmount,
    a.CommentsGiven,
    a.TotalCommentScore,
    a.Edits,
    a.EditPosts,
    a.SuggestedEdits,
    (
        a.TotalScore*2 + a.TotalViews/10 + a.GoldBadges*50 + a.SilverBadges*20 + a.BronzeBadges*5
        + a.UpVotesGiven + a.Edits*2 + a.SuggestedEdits*4 + a.CommentsGiven
        + a.BountiesGiven*10 + a.TotalBountyAmount/100
    ) AS ActivityScore
FROM ActivitySummary a
ORDER BY ActivityScore DESC
LIMIT 100;