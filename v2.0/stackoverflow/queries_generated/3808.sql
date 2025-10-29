-- {"query": "3808.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2041} 

WITH BadgeAgg AS (
    SELECT u.Id AS UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
PostAgg AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) AS VoteCountLast30Days
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),
UserRanks AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(b.GoldBadges,0) AS GoldBadges,
           COALESCE(b.SilverBadges,0) AS SilverBadges,
           COALESCE(b.BronzeBadges,0) AS BronzeBadges,
           COALESCE(p.QuestionCount,0) AS QuestionCount,
           COALESCE(p.AnswerCount,0) AS AnswerCount,
           COALESCE(p.AvgScore,0) AS AvgScore,
           COALESCE(p.LastPostDate, TIMESTAMP '1970-01-01') AS LastPostDate,
           COALESCE(v.VoteCountLast30Days,0) AS RecentVoteCount,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC,
                                      COALESCE(b.GoldBadges,0) DESC) AS RankByRep
    FROM Users u
    LEFT JOIN BadgeAgg b ON b.UserId = u.Id
    LEFT JOIN PostAgg p ON p.UserId = u.Id
    LEFT JOIN RecentVotes v ON v.UserId = u.Id
),
TagBadgeBreakdown AS (
    SELECT b.UserId,
           t.TagName,
           COUNT(*) AS TagBadgeCount
    FROM Badges b
    JOIN Tags t ON b.Name = t.TagName AND b.TagBased = 1
    GROUP BY b.UserId, t.TagName
),
FinalResult AS (
    SELECT ur.Id,
           ur.DisplayName,
           ur.Reputation,
           ur.GoldBadges,
           ur.SilverBadges,
           ur.BronzeBadges,
           ur.QuestionCount,
           ur.AnswerCount,
           ROUND(ur.AvgScore::numeric,2) AS AvgScoreRounded,
           ur.LastPostDate,
           ur.RecentVoteCount,
           ur.RankByRep,
           COALESCE(tb.TagBadgeCount,0) AS TagBadgeCount,
           tb.TagName
    FROM UserRanks ur
    LEFT JOIN TagBadgeBreakdown tb ON tb.UserId = ur.Id
    WHERE ur.RankByRep <= 100
      AND (ur.RecentVoteCount > 0 OR tb.TagBadgeCount > 0)
      AND ur.DisplayName IS NOT NULL
      AND ur.DisplayName <> ''
      AND (ur.LastPostDate > CURRENT_DATE - INTERVAL '5 years')
),
AllUsers AS (
    SELECT Id,
           DisplayName,
           NULL::int AS Reputation,
           0 AS GoldBadges,
           0 AS SilverBadges,
           0 AS BronzeBadges,
           0 AS QuestionCount,
           0 AS AnswerCount,
           0::numeric AS AvgScoreRounded,
           NULL::timestamp AS LastPostDate,
           0 AS RecentVoteCount,
           NULL::int AS RankByRep,
           0 AS TagBadgeCount,
           NULL::varchar AS TagName
    FROM Users
    WHERE Reputation = 0
      AND Id NOT IN (SELECT Id FROM FinalResult)
)
SELECT *
FROM FinalResult
UNION ALL
SELECT *
FROM AllUsers
ORDER BY RankByRep NULLS LAST,
         Reputation DESC,
         GoldBadges DESC
LIMIT 150;
