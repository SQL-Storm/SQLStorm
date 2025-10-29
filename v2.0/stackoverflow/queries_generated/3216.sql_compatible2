WITH 
    UserPostStats AS (
        SELECT 
            u.Id                     AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            COALESCE(SUM(p.Score), 0)               AS TotalScore,
            MAX(p.CreationDate)                    AS LastPostDate,
            MAX(p.LastActivityDate)                AS LastActivityDate
        FROM Users u
        LEFT JOIN Posts p 
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    UserBadgeStats AS (
        SELECT 
            b.UserId,
            COUNT(*)                                           AS BadgeTotal,
            COUNT(*) FILTER (WHERE b.Class = 1)                AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2)                AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3)                AS BronzeBadges,
            COUNT(*) FILTER (WHERE b.TagBased = TRUE)          AS TagBasedBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    UserVoteStats AS (
        SELECT 
            v.UserId,
            COUNT(*) FILTER (WHERE vt.Name = 'UpMod')          AS UpVotesCast,
            COUNT(*) FILTER (WHERE vt.Name = 'DownMod')        AS DownVotesCast,
            COUNT(*) FILTER (WHERE vt.Name = 'Favorite')       AS FavoritesCast
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ),
    UserTagOverlap AS (
        SELECT 
            p.OwnerUserId                                    AS UserId,
            COUNT(DISTINCT pt.Tag) FILTER (WHERE t.TagName IS NOT NULL) AS MatchingTagCount
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(
                     regexp_replace(p.Tags, '^<|>$', '', 'g'), '><')) AS Tag
        ) pt
        LEFT JOIN Tags t ON t.TagName = pt.Tag
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    RankedUsers AS (
        SELECT 
            ups.UserId,
            ups.DisplayName,
            ups.Reputation,
            ups.QuestionCount,
            ups.AnswerCount,
            ups.TotalScore,
            COALESCE(ub.GoldBadges, 0)    AS GoldBadges,
            COALESCE(ub.SilverBadges, 0)  AS SilverBadges,
            COALESCE(ub.BronzeBadges, 0)  AS BronzeBadges,
            COALESCE(uv.UpVotesCast, 0)   AS UpVotesCast,
            COALESCE(uv.DownVotesCast, 0) AS DownVotesCast,
            COALESCE(uto.MatchingTagCount, 0)                AS MatchingTagCount,
            ROW_NUMBER() OVER (ORDER BY ups.Reputation DESC, ups.TotalScore DESC) AS RepScoreRank,
            RANK()       OVER (ORDER BY (ups.QuestionCount + ups.AnswerCount) DESC) AS ActivityRank
        FROM UserPostStats ups
        LEFT JOIN UserBadgeStats ub ON ub.UserId = ups.UserId
        LEFT JOIN UserVoteStats  uv ON uv.UserId = ups.UserId
        LEFT JOIN UserTagOverlap uto ON uto.UserId = ups.UserId
    ),
    TopUsers AS (
        SELECT
            ru.UserId,
            ru.DisplayName,
            ru.Reputation,
            ru.QuestionCount,
            ru.AnswerCount,
            ru.TotalScore,
            ru.GoldBadges,
            ru.SilverBadges,
            ru.BronzeBadges,
            ru.UpVotesCast,
            ru.DownVotesCast,
            ru.MatchingTagCount,
            ru.RepScoreRank,
            ru.ActivityRank,
            CASE 
                WHEN ru.RepScoreRank <= 10  THEN 'Top10'
                WHEN ru.RepScoreRank <= 100 THEN 'Top100'
                ELSE 'Other'
            END AS Tier
        FROM RankedUsers ru
        WHERE ru.Reputation IS NOT NULL
        ORDER BY ru.RepScoreRank
        LIMIT 100
    ),
    SummaryRow AS (
        SELECT
            CAST(NULL AS bigint)        AS UserId,
            'Summary'                   AS DisplayName,
            SUM(r.Reputation)           AS Reputation,
            SUM(r.QuestionCount)        AS QuestionCount,
            SUM(r.AnswerCount)          AS AnswerCount,
            SUM(r.TotalScore)           AS TotalScore,
            SUM(r.GoldBadges)           AS GoldBadges,
            SUM(r.SilverBadges)         AS SilverBadges,
            SUM(r.BronzeBadges)         AS BronzeBadges,
            SUM(r.UpVotesCast)          AS UpVotesCast,
            SUM(r.DownVotesCast)        AS DownVotesCast,
            SUM(r.MatchingTagCount)     AS MatchingTagCount,
            CAST(NULL AS integer)       AS RepScoreRank,
            CAST(NULL AS integer)       AS ActivityRank,
            'Aggregate'                 AS Tier
        FROM RankedUsers r
        WHERE r.RepScoreRank <= 100
    )

SELECT * FROM TopUsers
UNION ALL
SELECT * FROM SummaryRow;