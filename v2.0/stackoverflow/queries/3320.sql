-- {"query": "3320.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2875}
WITH UserPostStats AS (
    SELECT 
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)               FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id)               FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        AVG(p.Score)              FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score)              FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*)                                      AS TotalBadges,
        COUNT(*)               FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*)               FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*)               FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ',')             AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),

UserVoteStats AS (
    SELECT 
        p.OwnerUserId                                      AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
),

Aggregated AS (
    SELECT 
        up.UserId,
        up.DisplayName,
        up.Reputation,
        up.QuestionCount,
        up.AnswerCount,
        up.AcceptedAnswerCount,
        COALESCE(up.AvgQuestionScore,0) AS AvgQuestionScore,
        COALESCE(up.AvgAnswerScore,0)   AS AvgAnswerScore,
        COALESCE(ub.TotalBadges,0)      AS TotalBadges,
        COALESCE(ub.GoldBadges,0)       AS GoldBadges,
        COALESCE(ub.SilverBadges,0)     AS SilverBadges,
        COALESCE(ub.BronzeBadges,0)     AS BronzeBadges,
        ub.BadgeList,
        COALESCE(vs.UpVotesReceived,0)      AS UpVotesReceived,
        COALESCE(vs.DownVotesReceived,0)    AS DownVotesReceived,
        COALESCE(vs.FavoritesReceived,0)    AS FavoritesReceived
    FROM UserPostStats up
    LEFT JOIN UserBadgeStats ub ON ub.UserId = up.UserId
    LEFT JOIN UserVoteStats vs  ON vs.UserId = up.UserId
),

Ranked AS (
    SELECT 
        a.*,
        ROW_NUMBER() OVER (ORDER BY a.Reputation DESC, a.TotalBadges DESC, a.UpVotesReceived DESC)   AS RankByReputation,
        RANK()       OVER (ORDER BY (a.UpVotesReceived - a.DownVotesReceived) DESC)                AS RankByVoteBalance,
        NTILE(4)     OVER (ORDER BY a.Reputation DESC)                                            AS RepQuartile
    FROM Aggregated a
),

MainResult AS (
    SELECT 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.QuestionCount,
        r.AnswerCount,
        r.AcceptedAnswerCount,
        r.AvgQuestionScore,
        r.AvgAnswerScore,
        r.TotalBadges,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        r.BadgeList,
        r.UpVotesReceived,
        r.DownVotesReceived,
        r.FavoritesReceived,
        r.RankByReputation,
        r.RankByVoteBalance,
        r.RepQuartile,
        CASE 
            WHEN r.TotalBadges = 0                         THEN 'No Badges'
            WHEN r.GoldBadges   > 0                         THEN 'Gold Badge Owner'
            WHEN r.SilverBadges > 0                         THEN 'Silver Badge Owner'
            ELSE                                               'Badge Holder'
        END                                            AS BadgeTier,
        COALESCE(NULLIF(r.FavoritesReceived,0), NULL) AS FirstFavoriteOrNull
    FROM Ranked r
    WHERE r.RankByReputation <= 100
       OR (r.Reputation BETWEEN 1000 AND 2000 AND r.RepQuartile = 2)
       OR EXISTS (
            SELECT 1
            FROM Posts p
            WHERE p.OwnerUserId = r.UserId
              AND p.PostTypeId = 2
              AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30 day')
              AND p.Score > 10
       )
)

SELECT * FROM MainResult
UNION ALL
SELECT 
    -1                                          AS UserId,
    'Anonymous'                                 AS DisplayName,
    0                                           AS Reputation,
    0                                           AS QuestionCount,
    0                                           AS AnswerCount,
    0                                           AS AcceptedAnswerCount,
    0                                           AS AvgQuestionScore,
    0                                           AS AvgAnswerScore,
    0                                           AS TotalBadges,
    0                                           AS GoldBadges,
    0                                           AS SilverBadges,
    0                                           AS BronzeBadges,
    NULL                                        AS BadgeList,
    0                                           AS UpVotesReceived,
    0                                           AS DownVotesReceived,
    0                                           AS FavoritesReceived,
    NULL                                        AS RankByReputation,
    NULL                                        AS RankByVoteBalance,
    NULL                                        AS RepQuartile,
    'No Badges'                                 AS BadgeTier,
    NULL                                        AS FirstFavoriteOrNull
ORDER BY Reputation DESC, UserId;