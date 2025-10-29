WITH UserPostStats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 1), 0) AS QuestionScore,
           COALESCE(SUM(p.Score) FILTER (WHERE p.PostTypeId = 2), 0) AS AnswerScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadgeStats AS (
    SELECT b.UserId,
           COUNT(*) AS TotalBadges,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserTagStats AS (
    SELECT u.Id AS UserId,
           taglist.TagName,
           COUNT(*) AS TagUsage,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
                 AND p.PostTypeId = 1
                 AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    ) AS taglist
    JOIN Tags t ON t.TagName = taglist.TagName
    GROUP BY u.Id, taglist.TagName
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
           MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
MainResults AS (
    SELECT up.UserId,
           up.DisplayName,
           up.Reputation,
           up.QuestionCount,
           up.AnswerCount,
           up.QuestionScore,
           up.AnswerScore,
           COALESCE(ub.TotalBadges, 0)      AS TotalBadges,
           COALESCE(ub.GoldBadges, 0)       AS GoldBadges,
           COALESCE(ub.SilverBadges, 0)     AS SilverBadges,
           COALESCE(ub.BronzeBadges, 0)     AS BronzeBadges,
           COALESCE(rv.UpVotesGiven, 0)     AS UpVotesGiven,
           COALESCE(rv.DownVotesGiven, 0)   AS DownVotesGiven,
           up.LastPostDate,
           rv.LastVoteDate,
           STRING_AGG(DISTINCT CASE WHEN uts.TagRank = 1 THEN uts.TagName END, ', ') FILTER (WHERE uts.TagRank = 1) AS TopTag,
           CASE
               WHEN up.Reputation > 20000 THEN 'Legendary'
               WHEN up.Reputation > 10000 THEN 'Expert'
               WHEN up.Reputation > 5000  THEN 'Advanced'
               ELSE 'Novice'
           END AS ReputationTier,
           CASE WHEN EXISTS (
               SELECT 1
               FROM Posts a
               WHERE a.OwnerUserId = up.UserId
                 AND a.PostTypeId = 2
                 AND a.AcceptedAnswerId IS NOT NULL
           ) THEN TRUE ELSE FALSE END AS HasAcceptedAnswers
    FROM UserPostStats up
    LEFT JOIN UserBadgeStats ub ON ub.UserId = up.UserId
    LEFT JOIN RecentVotes rv   ON rv.UserId = up.UserId
    LEFT JOIN UserTagStats uts ON uts.UserId = up.UserId AND uts.TagRank <= 3
    GROUP BY up.UserId, up.DisplayName, up.Reputation,
             up.QuestionCount, up.AnswerCount,
             up.QuestionScore, up.AnswerScore,
             ub.TotalBadges, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
             rv.UpVotesGiven, rv.DownVotesGiven,
             up.LastPostDate, rv.LastVoteDate
    HAVING COUNT(*) FILTER (WHERE up.QuestionCount > 0) > 0
    ORDER BY up.Reputation DESC NULLS LAST
    LIMIT 100
)

SELECT * FROM MainResults

UNION ALL

SELECT CAST(NULL AS BIGINT) AS UserId,
       CAST(NULL AS TEXT) AS DisplayName,
       CAST(NULL AS BIGINT) AS Reputation,
       CAST(NULL AS BIGINT) AS QuestionCount,
       CAST(NULL AS BIGINT) AS AnswerCount,
       CAST(NULL AS BIGINT) AS QuestionScore,
       CAST(NULL AS BIGINT) AS AnswerScore,
       CAST(NULL AS BIGINT) AS TotalBadges,
       CAST(NULL AS BIGINT) AS GoldBadges,
       CAST(NULL AS BIGINT) AS SilverBadges,
       CAST(NULL AS BIGINT) AS BronzeBadges,
       CAST(NULL AS BIGINT) AS UpVotesGiven,
       CAST(NULL AS BIGINT) AS DownVotesGiven,
       CAST(NULL AS TIMESTAMP) AS LastPostDate,
       CAST(NULL AS TIMESTAMP) AS LastVoteDate,
       CAST(NULL AS TEXT) AS TopTag,
       CAST(NULL AS TEXT) AS ReputationTier,
       CAST(NULL AS BOOLEAN) AS HasAcceptedAnswers
FROM (SELECT 1) dummy
WHERE NOT EXISTS (SELECT 1 FROM Users);