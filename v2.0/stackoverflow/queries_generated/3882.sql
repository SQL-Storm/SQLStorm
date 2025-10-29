-- {"query": "3882.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2319} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)                         AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                                 AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                                 AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                                 AS BronzeBadges,
        MAX(u.LastAccessDate)                                                  AS LastSeen,
        MIN(u.CreationDate)                                                    AS Joined,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                         AS RepRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
PostAggregates AS (
    SELECT
        p.OwnerUserId                                          AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)               AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)               AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)           AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)           AS AvgAnswerScore,
        MAX(p.CreationDate)                                   AS LastPostDate,
        SUM(COALESCE(p.FavoriteCount,0))                       AS TotalFavorites,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM '\<([^>]+)\>'), ',')
                                                                FILTER (WHERE p.Tags IS NOT NULL) AS TagBag
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentVotes AS (
    SELECT
        v.PostId,
        MAX(v.CreationDate)                                   AS LastVoteDate,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2)              AS UpVoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3)              AS DownVoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5)              AS FavoriteCount
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
),
TopLinkedPosts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name                                               AS LinkType,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
UserLinkInfo AS (
    SELECT
        p.OwnerUserId                                          AS UserId,
        COUNT(DISTINCT tl.RelatedPostId)                      AS DistinctLinkedPosts,
        COUNT(*) FILTER (WHERE tl.LinkType = 'Duplicate')    AS DuplicateLinks
    FROM Posts p
    LEFT JOIN TopLinkedPosts tl ON tl.PostId = p.Id AND tl.rn = 1
    GROUP BY p.OwnerUserId
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.RepRank,
    COALESCE(pa.QuestionCount,0)       AS Questions,
    COALESCE(pa.AnswerCount,0)         AS Answers,
    ROUND(COALESCE(pa.AvgQuestionScore,0)::numeric,2) AS AvgQScore,
    ROUND(COALESCE(pa.AvgAnswerScore,0)::numeric,2)   AS AvgAScore,
    pa.TotalFavorites,
    pa.TagBag,
    rv.LastVoteDate,
    rv.UpVoteCount,
    rv.DownVoteCount,
    rv.FavoriteCount,
    ul.DistinctLinkedPosts,
    ul.DuplicateLinks,
    CASE
        WHEN us.Reputation > 20000 THEN 'Veteran'
        WHEN us.Reputation > 10000 THEN 'Seasoned'
        WHEN us.Reputation > 5000  THEN 'Active'
        ELSE 'Newbie'
    END                               AS ReputationTier,
    COALESCE(us.LastSeen, us.Joined)  AS LastActivity,
    (SELECT COUNT(*) FROM Comments c
        WHERE c.UserId = us.Id
          AND c.CreationDate > CURRENT_DATE - INTERVAL '7 days') AS RecentCommentCount
FROM UserStats us
LEFT JOIN PostAggregates pa ON pa.UserId = us.Id
LEFT JOIN RecentVotes rv ON rv.PostId = (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = us.Id
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN UserLinkInfo ul ON ul.UserId = us.Id
WHERE us.RepRank <= 1000
ORDER BY us.RepRank
LIMIT 100
UNION ALL
SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
LIMIT 0;
