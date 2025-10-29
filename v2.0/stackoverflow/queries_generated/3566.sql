-- {"query": "3566.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3470} 

WITH
UserStats AS (
    SELECT
        u.Id                                         AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)       AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)       AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)       AS BronzeBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)   AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Votes v    ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
RecentQuestionPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.FavoriteCount,
        COALESCE(p.ClosedDate, p.CreationDate)     AS EffectiveDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RN
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
PostVoteAgg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
CommentCounts AS (
    SELECT
        c.PostId,
        COUNT(*)                                   AS CommentCount,
        MAX(c.CreationDate)                        AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
TagExploded AS (
    SELECT
        p.Id                                          AS PostId,
        TRIM(BOTH '><' FROM UNNEST(string_to_array(substr(p.Tags,2,length(p.Tags)-2), '><'))) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
TagStats AS (
    SELECT
        te.TagName,
        COUNT(*)                                      AS TagUsage,
        AVG(p.Score)                                  AS AvgScore,
        SUM(p.ViewCount)                              AS TotalViews
    FROM TagExploded te
    JOIN Posts p ON p.Id = te.PostId
    GROUP BY te.TagName
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.ReputationRank,
    q.Id                                         AS QuestionId,
    q.Title,
    q.Score                                      AS QuestionScore,
    q.ViewCount,
    q.FavoriteCount,
    COALESCE(pva.UpVoteCount,0)                  AS QuestionUpVotes,
    COALESCE(pva.DownVoteCount,0)                AS QuestionDownVotes,
    COALESCE(cc.CommentCount,0)                  AS QuestionCommentCount,
    STRING_AGG(DISTINCT te.TagName, ',')         AS Tags,
    CASE
        WHEN q.ClosedDate IS NOT NULL            THEN 'Closed'
        WHEN q.CommunityOwnedDate IS NOT NULL    THEN 'Community'
        ELSE 'Open'
    END                                          AS Status,
    COALESCE(q.AnswerCount,0)                    AS AnswerCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS ActualAnswerCount,
    (SELECT MAX(a.Score) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS TopAnswerScore,
    (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
    (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS FirstAnswerDate,
    (SELECT MAX(a.CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS LastAnswerDate,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = q.OwnerUserId AND b.Class = 1) AS OwnerGoldBadges,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2)      AS OwnerUpVotesOnPost,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = q.Id AND pl.LinkTypeId = 1) AS IncomingLinkCount,
    ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS QuestionRankByScore
FROM UserStats us
LEFT JOIN RecentQuestionPosts q      ON q.OwnerUserId = us.UserId AND q.RN = 1
LEFT JOIN PostVoteAgg pva           ON pva.PostId = q.Id
LEFT JOIN CommentCounts cc          ON cc.PostId = q.Id
LEFT JOIN TagExploded te            ON te.PostId = q.Id
WHERE us.Reputation > 10000
GROUP BY
    us.UserId, us.DisplayName, us.Reputation, us.GoldBadges, us.SilverBadges,
    us.BronzeBadges, us.ReputationRank,
    q.Id, q.Title, q.Score, q.ViewCount, q.FavoriteCount,
    q.ClosedDate, q.CommunityOwnedDate, q.AnswerCount,
    pva.UpVoteCount, pva.DownVoteCount, cc.CommentCount
ORDER BY us.ReputationRank
LIMIT 50

UNION ALL

SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    p.Id                                 AS QuestionId,
    p.Title,
    p.Score                              AS QuestionScore,
    p.ViewCount,
    p.FavoriteCount,
    COALESCE(pva.UpVoteCount,0)          AS QuestionUpVotes,
    COALESCE(pva.DownVoteCount,0)        AS QuestionDownVotes,
    COALESCE(cc.CommentCount,0)          AS QuestionCommentCount,
    STRING_AGG(DISTINCT te.TagName, ',') AS Tags,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS Status,
    p.AnswerCount,
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS QuestionRankByScore
FROM Posts p
LEFT JOIN PostVoteAgg pva ON pva.PostId = p.Id
LEFT JOIN CommentCounts cc ON cc.PostId = p.Id
LEFT JOIN TagExploded te   ON te.PostId = p.Id
WHERE p.PostTypeId = 1
  AND p.CreationDate > CURRENT_DATE - INTERVAL '7 days'
GROUP BY
    p.Id, p.Title, p.Score, p.ViewCount, p.FavoriteCount,
    p.ClosedDate, p.AnswerCount, pva.UpVoteCount, pva.DownVoteCount, cc.CommentCount
ORDER BY p.Score DESC
LIMIT 20;
