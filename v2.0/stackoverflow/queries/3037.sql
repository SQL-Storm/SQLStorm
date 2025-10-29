-- {"query": "3037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2584} 
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.CreationDate, TIMESTAMP '1970-01-01') AS UserCreated,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
           MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
BadgeStats AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagAgg AS (
    SELECT p.OwnerUserId AS UserId,
           STRING_AGG(DISTINCT t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS TagsUsed,
           COUNT(DISTINCT t.TagName) AS DistinctTagCount
    FROM Posts p
    JOIN LATERAL (
        SELECT regexp_split_to_table(p.Tags, '[><]') AS raw_tag
    ) AS tag_raw ON true
    LEFT JOIN Tags t ON t.TagName = replace(replace(tag_raw.raw_tag, '<', ''), '>', '')
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentVotes AS (
    SELECT v.UserId,
           COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesCast,
           COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesCast,
           MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
RankedUsers AS (
    SELECT us.Id,
           us.DisplayName,
           us.Reputation,
           us.QuestionCount,
           us.AnswerCount,
           us.AvgPostScore,
           us.LastPostActivity,
           bs.GoldBadges,
           bs.SilverBadges,
           bs.BronzeBadges,
           bs.TotalBadges,
           ta.TagsUsed,
           ta.DistinctTagCount,
           rv.UpVotesCast,
           rv.DownVotesCast,
           rv.LastVoteDate,
           ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.AvgPostScore DESC NULLS LAST) AS ReputationRank,
           RANK()   OVER (ORDER BY (COALESCE(bs.TotalBadges,0) + us.QuestionCount + us.AnswerCount) DESC) AS ActivityRank
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
    LEFT JOIN TagAgg    ta ON ta.UserId = us.Id
    LEFT JOIN RecentVotes rv ON rv.UserId = us.Id
)
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    COALESCE(ru.AvgPostScore,0)      AS AvgPostScore,
    ru.LastPostActivity,
    COALESCE(ru.GoldBadges,0)        AS GoldBadges,
    COALESCE(ru.SilverBadges,0)      AS SilverBadges,
    COALESCE(ru.BronzeBadges,0)      AS BronzeBadges,
    COALESCE(ru.TotalBadges,0)       AS TotalBadges,
    COALESCE(ru.TagsUsed,'')         AS TagsUsed,
    COALESCE(ru.DistinctTagCount,0)  AS DistinctTagCount,
    COALESCE(ru.UpVotesCast,0)       AS UpVotesCast,
    COALESCE(ru.DownVotesCast,0)     AS DownVotesCast,
    ru.LastVoteDate,
    ru.ReputationRank,
    ru.ActivityRank,
    CASE
        WHEN ru.ReputationRank <= 10  THEN 'Top10'
        WHEN ru.ReputationRank <= 100 THEN 'Top100'
        ELSE 'Other'
    END                              AS ReputationTier
FROM RankedUsers ru
WHERE ru.Reputation IS NOT NULL

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0 AS QuestionCount,
    0 AS AnswerCount,
    0 AS AvgPostScore,
    NULL AS LastPostActivity,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS TotalBadges,
    '' AS TagsUsed,
    0 AS DistinctTagCount,
    0 AS UpVotesCast,
    0 AS DownVotesCast,
    NULL AS LastVoteDate,
    NULL AS ReputationRank,
    NULL AS ActivityRank,
    'NoActivity' AS ReputationTier
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation < 100

ORDER BY ReputationRank ASC NULLS LAST, Reputation DESC
LIMIT 50;