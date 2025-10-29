WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.Views, 0) AS TotalViews,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           MAX(u.LastAccessDate) AS LastSeen,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.LastAccessDate
),
ScoreStats AS (
    SELECT p.OwnerUserId AS UserId,
           AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
           AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.PostTypeId = 2) AS MedianAnswerScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesGiven,
           COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
           COUNT(*) FILTER (WHERE vt.Name = 'Favorite') AS FavoritesGiven
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY v.UserId
),
TagActivity AS (
    SELECT p.OwnerUserId AS UserId,
           STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM t.TagName), ',') AS TagsUsed,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithTags
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName
    ) t ON TRUE
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),
MainRows AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.TotalViews,
           us.BadgeCount,
           us.GoldBadges,
           us.SilverBadges,
           us.BronzeBadges,
           us.QuestionCount,
           us.AnswerCount,
           ss.AvgQuestionScore,
           ss.AvgAnswerScore,
           ss.MedianAnswerScore,
           rv.UpVotesGiven,
           rv.DownVotesGiven,
           rv.FavoritesGiven,
           ta.TagsUsed,
           ta.QuestionsWithTags,
           CASE 
               WHEN us.Reputation > 20000 THEN 'Legendary'
               WHEN us.Reputation > 10000 THEN 'Expert'
               WHEN us.Reputation > 5000 THEN 'Seasoned'
               ELSE 'Community'
           END AS ReputationTier,
           COALESCE(us.LastSeen, TIMESTAMP '1970-01-01 00:00:00') AS LastSeen
    FROM UserStats us
    LEFT JOIN ScoreStats ss ON ss.UserId = us.Id
    LEFT JOIN RecentVotes rv ON rv.UserId = us.Id
    LEFT JOIN TagActivity ta ON ta.UserId = us.Id
    WHERE (us.QuestionCount + us.AnswerCount) > 0
      AND us.Reputation IS NOT NULL
)
SELECT *
FROM (
    SELECT *
    FROM MainRows
    ORDER BY Reputation DESC
    FETCH FIRST 100 ROWS ONLY
) t

UNION ALL

SELECT
    NULL AS Id,
    'Aggregated Totals' AS DisplayName,
    SUM(us.Reputation) AS Reputation,
    SUM(us.TotalViews) AS TotalViews,
    SUM(us.BadgeCount) AS BadgeCount,
    SUM(us.GoldBadges) AS GoldBadges,
    SUM(us.SilverBadges) AS SilverBadges,
    SUM(us.BronzeBadges) AS BronzeBadges,
    SUM(us.QuestionCount) AS QuestionCount,
    SUM(us.AnswerCount) AS AnswerCount,
    AVG(ss.AvgQuestionScore) AS AvgQuestionScore,
    AVG(ss.AvgAnswerScore) AS AvgAnswerScore,
    NULL AS MedianAnswerScore,
    SUM(rv.UpVotesGiven) AS UpVotesGiven,
    SUM(rv.DownVotesGiven) AS DownVotesGiven,
    SUM(rv.FavoritesGiven) AS FavoritesGiven,
    NULL AS TagsUsed,
    NULL AS QuestionsWithTags,
    NULL AS ReputationTier,
    NULL AS LastSeen
FROM UserStats us
LEFT JOIN ScoreStats ss ON ss.UserId = us.Id
LEFT JOIN RecentVotes rv ON rv.UserId = us.Id
WHERE us.Reputation > 0;