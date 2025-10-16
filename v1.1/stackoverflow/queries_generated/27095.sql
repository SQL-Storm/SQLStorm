-- {"query": "27095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1060} 

WITH RankedUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM
        Users u
    WHERE
        u.Reputation > 1000
),
TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 AND p.Score > 50
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
TopVotedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        COALESCE(SUM(v.VoteTypeId = 2), 0) AS UpVotes,
        COALESCE(SUM(v.VoteTypeId = 3), 0) AS DownVotes
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    GROUP BY
        p.Id,
        p.Title,
        p.OwnerUserId
    HAVING
        COALESCE(SUM(v.VoteTypeId = 2), 0) > 10
),
ActiveComments AS (
    SELECT
        c.PostId,
        c.UserId,
        c.CreationDate,
        LAG(c.CreationDate) OVER (PARTITION BY c.PostId ORDER BY c.CreationDate) AS PreviousCommentDate,
        c.Text
    FROM
        Comments c
    WHERE
        c.CreationDate > NOW() - INTERVAL '30 days'
    )
SELECT
    r.UserId,
    r.Reputation,
    r.DisplayName,
    r.ReputationRank,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    tp.PostRank,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    tvp.UpVotes,
    tvp.DownVotes,
    MIN(ac.CreationDate) AS FirstCommentDate
FROM
    RankedUsers r
LEFT JOIN
    TopPosts tp ON r.UserId = tp.OwnerUserId
LEFT JOIN
    UserBadges ub ON r.UserId = ub.UserId
LEFT JOIN
    TopVotedPosts tvp ON r.UserId = tvp.OwnerUserId
INNER JOIN
    ActiveComments ac ON r.UserId = ac.UserId AND ac.UserId IS NOT NULL AND NOT EXISTS
 (SELECT 1
  FROM ActiveComments AS iac
  WHERE iac.UserId=ac.UserId
    AND iac.CreationDate=ac.PreviousCommentDate
 )
GROUP BY
    r.UserId,
    r.Reputation,
    r.DisplayName,
    r.ReputationRank,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    tp.PostRank,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    tvp.UpVotes,
    tvp.DownVote
ORDER BY
    r.ReputationRank ASC,
    tp.PostRank ASC;
