-- {"query": "3412.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2556} 

WITH
    UserBadgeCounts AS (
        SELECT
            u.Id AS UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS BronzeBadges,
            COUNT(b.Id)                                    AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),
    UserPostStats AS (
        SELECT
            u.Id AS UserId,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                        AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                        AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)                   AS AvgPostScore,
            SUM(p.ViewCount) FILTER (WHERE p.ViewCount IS NOT NULL)           AS TotalViews,
            MAX(p.LastActivityDate)                                            AS LastPostActivity,
            STRING_AGG(
                DISTINCT TRIM(BOTH '><' FROM regexp_replace(p.Tags, '^<|>$', '', 'g')),
                ','
            ) FILTER (WHERE p.Tags IS NOT NULL)                               AS TagList
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),
    UserRecentActivity AS (
        SELECT
            u.Id AS UserId,
            GREATEST(
                COALESCE(u.LastAccessDate, u.CreationDate),
                COALESCE(up.LastPostActivity, u.CreationDate)
            )                                                                      AS MostRecentActivity,
            DATE_PART(
                'day',
                CURRENT_TIMESTAMP - GREATEST(
                    COALESCE(u.LastAccessDate, u.CreationDate),
                    COALESCE(up.LastPostActivity, u.CreationDate)
                )
            )                                                                      AS DaysSinceLastActivity
        FROM Users u
        LEFT JOIN (
            SELECT
                OwnerUserId AS UserId,
                MAX(LastActivityDate) AS LastPostActivity
            FROM Posts
            GROUP BY OwnerUserId
        ) up ON up.UserId = u.Id
    ),
    UserScoreDetails AS (
        SELECT
            u.Id AS UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 5)      AS FavoritesReceived
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY u.Id
    ),
    RankedUsers AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ub.GoldBadges,
            ub.SilverBadges,
            ub.BronzeBadges,
            ups.QuestionCount,
            ups.AnswerCount,
            ups.AvgPostScore,
            ups.TotalViews,
            upra.DaysSinceLastActivity,
            usd.UpVotesReceived,
            usd.DownVotesReceived,
            usd.FavoritesReceived,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, ub.GoldBadges DESC) AS RepRank,
            NTILE(4) OVER (ORDER BY u.Reputation DESC)                         AS ReputationQuartile,
            CASE
                WHEN ub.GoldBadges > 0                     THEN 'Elite'
                WHEN ub.SilverBadges > 5                   THEN 'Pro'
                WHEN ub.BronzeBadges > 10                  THEN 'Rising'
                ELSE 'Newbie'
            END                                                                  AS BadgeTier,
            COALESCE(ups.TagList, '')                                          AS ContributedTags
        FROM Users u
        LEFT JOIN UserBadgeCounts ub    ON ub.UserId = u.Id
        LEFT JOIN UserPostStats ups    ON ups.UserId = u.Id
        LEFT JOIN UserRecentActivity upra ON upra.UserId = u.Id
        LEFT JOIN UserScoreDetails usd ON usd.UserId = u.Id
    )
SELECT
    *
FROM RankedUsers
WHERE RepRank <= 100
  AND DaysSinceLastActivity <= 30

UNION ALL

SELECT
    NULL                                     AS Id,
    'Aggregate Summary'                      AS DisplayName,
    NULL                                     AS Reputation,
    SUM(GoldBadges)                          AS GoldBadges,
    SUM(SilverBadges)                        AS SilverBadges,
    SUM(BronzeBadges)                        AS BronzeBadges,
    SUM(QuestionCount)                       AS QuestionCount,
    SUM(AnswerCount)                         AS AnswerCount,
    AVG(AvgPostScore)                        AS AvgPostScore,
    SUM(TotalViews)                          AS TotalViews,
    NULL                                     AS DaysSinceLastActivity,
    SUM(UpVotesReceived)                     AS UpVotesReceived,
    SUM(DownVotesReceived)                   AS DownVotesReceived,
    SUM(FavoritesReceived)                   AS FavoritesReceived,
    NULL                                     AS RepRank,
    NULL                                     AS ReputationQuartile,
    NULL                                     AS BadgeTier,
    STRING_AGG(DISTINCT ContributedTags, ',')
        FILTER (WHERE ContributedTags <> '') AS ContributedTags
FROM RankedUsers
WHERE RepRank <= 100;
