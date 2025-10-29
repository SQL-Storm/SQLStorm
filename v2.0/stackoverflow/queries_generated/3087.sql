-- {"query": "3087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2829} 

WITH UserPostStats AS (
    SELECT 
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                         AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                         AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)                        AS QuestionScoreSum,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)                        AS AnswerScoreSum,
        COUNT(DISTINCT UNNEST(STRING_TO_ARRAY(
                 REGEXP_REPLACE(p.Tags, '^<|>$', ''), '><'))) FILTER (WHERE p.PostTypeId = 1) 
                                                                        AS DistinctTagCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1)        AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)        AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)        AS BronzeBadges,
        COUNT(*) FILTER (WHERE b.TagBased = 1)    AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),

UserVoteStats AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')      AS UpVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod')    AS DownVotesGiven,
        COUNT(*) FILTER (WHERE vt.Name = 'Favorite')   AS FavoritesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.UserId
),

UserLatestEdit AS (
    SELECT 
        p.OwnerUserId                               AS UserId,
        p.Id                                        AS PostId,
        MAX(ph.CreationDate)                        AS LastEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Text END) AS LastEditSnippet
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    GROUP BY p.OwnerUserId, p.Id
),

RankedUsers AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.QuestionScoreSum,
        ups.AnswerScoreSum,
        COALESCE(ubs.GoldBadges,0)   AS GoldBadges,
        COALESCE(ubs.SilverBadges,0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges,0) AS BronzeBadges,
        COALESCE(uvs.UpVotesGiven,0) AS UpVotesGiven,
        COALESCE(uvs.DownVotesGiven,0) AS DownVotesGiven,
        (ups.QuestionScoreSum + ups.AnswerScoreSum) 
            + (ups.Reputation * 0.1) 
            + (COALESCE(ubs.GoldBadges,0)   * 100) 
            + (COALESCE(ubs.SilverBadges,0) * 50) 
            + (COALESCE(ubs.BronzeBadges,0) * 20)                     AS CompositeScore,
        ROW_NUMBER() OVER (ORDER BY (ups.QuestionScoreSum + ups.AnswerScoreSum) DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY COALESCE(ubs.GoldBadges,0) DESC,
                                   COALESCE(ubs.SilverBadges,0) DESC)         AS BadgeRank
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs ON ubs.UserId = ups.UserId
    LEFT JOIN UserVoteStats uvs ON uvs.UserId = ups.UserId
)

SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.CompositeScore,
    ru.ScoreRank,
    ru.BadgeRank,
    COALESCE(ul.LastEditDate, TIMESTAMP '1970-01-01') AS LastEditDate,
    CASE 
        WHEN ru.BadgeRank = 1 THEN 'Top Badge Holder'
        WHEN ru.ScoreRank <= 10 THEN 'Top 10 Scorers'
        ELSE 'Other'
    END                                          AS Category,
    COALESCE(pl.DuplicateCount,0)                AS DuplicateLinkCount,
    COALESCE(pl.LinkedCount,0)                   AS LinkedCount
FROM RankedUsers ru
LEFT JOIN (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateCount,
        SUM(CASE WHEN lt.Name = 'Linked'    THEN 1 ELSE 0 END) AS LinkedCount
    FROM Posts p
    JOIN PostLinks pl ON pl.PostId = p.Id
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY p.OwnerUserId
) pl ON pl.OwnerUserId = ru.UserId
LEFT JOIN UserLatestEdit ul 
    ON ul.UserId = ru.UserId 
   AND ul.PostId = (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = ru.UserId
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
WHERE ru.Reputation > 1000
  AND (ru.QuestionCount IS NOT NULL OR ru.AnswerCount IS NOT NULL)

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    0                                            AS QuestionCount,
    0                                            AS AnswerCount,
    u.Reputation * 0.05                         AS CompositeScore,
    NULL                                         AS ScoreRank,
    NULL                                         AS BadgeRank,
    NULL                                         AS LastEditDate,
    'No Activity'                                AS Category,
    0                                            AS DuplicateLinkCount,
    0                                            AS LinkedCount
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation > 500

ORDER BY CompositeScore DESC
LIMIT 100;
