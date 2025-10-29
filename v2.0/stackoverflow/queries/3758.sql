-- {"query": "3758.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2033}
WITH
    UserBadges AS (
        SELECT
            u.Id AS UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            COUNT(b.Id) AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),
    UserPostStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
            AVG(p.Score) AS AvgScore,
            MAX(p.CreationDate) AS LastPostDate
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    UserRecentVotes AS (
        SELECT
            v.UserId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)       AS UpVotesGiven,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END)     AS DownVotesGiven,
            SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END)    AS FavoritesGiven
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
        GROUP BY v.UserId
    ),
    ClosedDuplicateQuestions AS (
        SELECT DISTINCT
            p.OwnerUserId AS UserId
        FROM Posts p
        JOIN PostHistory ph ON ph.PostId = p.Id
        JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
        WHERE p.PostTypeId = 1
          AND pht.Name = 'Post Closed'
          AND ph.Comment = '101'
    ),
    MainResult AS (
        SELECT
            u.Id,
            COALESCE(u.DisplayName, 'Anonymous')                     AS DisplayName,
            u.Reputation,
            ub.GoldBadges,
            ub.SilverBadges,
            ub.BronzeBadges,
            ub.TotalBadges,
            ups.QuestionCount,
            ups.AnswerCount,
            ROUND(ups.AvgScore, 2)                                   AS AvgPostScore,
            urv.UpVotesGiven,
            urv.DownVotesGiven,
            urv.FavoritesGiven,
            CASE WHEN cdq.UserId IS NOT NULL THEN 1 ELSE 0 END       AS HasClosedDuplicate,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC,
                                         ub.TotalBadges DESC)    AS ReputationRank,
            CONCAT('User-', u.Id, '-', REPLACE(COALESCE(u.DisplayName, ''), ' ', '_')) AS UserSlug,
            COALESCE(ups.LastPostDate, u.CreationDate)               AS MostRecentActivity
        FROM Users u
        LEFT JOIN UserBadges ub                ON ub.UserId = u.Id
        LEFT JOIN UserPostStats ups            ON ups.UserId = u.Id
        LEFT JOIN UserRecentVotes urv          ON urv.UserId = u.Id
        LEFT JOIN ClosedDuplicateQuestions cdq ON cdq.UserId = u.Id
        WHERE u.Reputation > 1000
          AND (ub.TotalBadges IS NULL OR ub.TotalBadges >= 5)
          AND (ups.QuestionCount IS NULL OR ups.QuestionCount >= 1)
        ORDER BY ReputationRank
        LIMIT 100
    )
SELECT *
FROM MainResult

UNION ALL

SELECT
    NULL AS Id,
    'SUMMARY' AS DisplayName,
    NULL AS Reputation,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    SUM(ub.TotalBadges)                     AS TotalBadges,
    SUM(ups.QuestionCount)                  AS QuestionCount,
    SUM(ups.AnswerCount)                    AS AnswerCount,
    NULL AS AvgPostScore,
    SUM(urv.UpVotesGiven)                   AS UpVotesGiven,
    SUM(urv.DownVotesGiven)                 AS DownVotesGiven,
    SUM(urv.FavoritesGiven)                 AS FavoritesGiven,
    NULL AS HasClosedDuplicate,
    NULL AS ReputationRank,
    NULL AS UserSlug,
    NULL AS MostRecentActivity
FROM UserBadges ub
FULL OUTER JOIN UserPostStats ups ON ups.UserId = ub.UserId
FULL OUTER JOIN UserRecentVotes urv ON urv.UserId = ub.UserId;