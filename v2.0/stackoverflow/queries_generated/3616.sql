-- {"query": "3616.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2421} 

WITH UserPosts AS (
    SELECT u.Id                                     AS UserId,
           u.DisplayName,
           u.Reputation,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
           SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
           MAX(p.CreationDate)                       AS LastPostDate
    FROM   Users u
    LEFT  JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadges AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames
    FROM   Badges b
    GROUP BY b.UserId
),
TagStats AS (
    SELECT u.Id                                     AS UserId,
           t.TagName,
           COUNT(*)                                 AS TagPostCount,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS rn
    FROM   Users u
    JOIN   Posts p
           ON p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    CROSS  JOIN LATERAL regexp_split_to_table(trim(both '<>' FROM p.Tags), '><') AS tag
    JOIN   Tags t
           ON t.TagName = tag
    GROUP BY u.Id, t.TagName
),
TopTags AS (
    SELECT UserId,
           TagName,
           TagPostCount
    FROM   TagStats
    WHERE  rn <= 3
),
UserVotes AS (
    SELECT p.OwnerUserId                                 AS UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
           COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 5) AS FavoritesReceived
    FROM   Posts p
    LEFT   JOIN Votes v
           ON v.PostId = p.Id
    WHERE  p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
Metrics AS (
    SELECT up.UserId,
           up.DisplayName,
           up.Reputation,
           up.QuestionCount,
           up.AnswerCount,
           COALESCE(up.QuestionScoreSum,0) AS QuestionScoreSum,
           COALESCE(up.AnswerScoreSum,0)   AS AnswerScoreSum,
           ub.GoldBadges,
           ub.SilverBadges,
           ub.BronzeBadges,
           ub.GoldBadgeNames,
           uv.UpVotesReceived,
           uv.DownVotesReceived,
           uv.FavoritesReceived,
           up.LastPostDate
    FROM   UserPosts  up
    LEFT   JOIN UserBadges ub ON ub.UserId = up.UserId
    LEFT   JOIN UserVotes uv  ON uv.UserId = up.UserId
),
FinalResult AS (
    SELECT m.*,
           STRING_AGG(t.TagName || ':' || t.TagPostCount, ', ') AS TopTags
    FROM   Metrics m
    LEFT   JOIN TopTags t ON t.UserId = m.UserId
    GROUP BY m.UserId, m.DisplayName, m.Reputation, m.QuestionCount,
             m.AnswerCount, m.QuestionScoreSum, m.AnswerScoreSum,
             m.GoldBadges, m.SilverBadges, m.BronzeBadges,
             m.GoldBadgeNames, m.UpVotesReceived, m.DownVotesReceived,
             m.FavoritesReceived, m.LastPostDate
)
SELECT *
FROM   FinalResult
WHERE  (Reputation > 10000 OR GoldBadges >= 5)
   AND (QuestionCount + AnswerCount) > 0
   AND COALESCE(QuestionScoreSum,0) + COALESCE(AnswerScoreSum,0) > 0
ORDER BY Reputation DESC NULLS LAST,
         GoldBadges DESC,
         QuestionCount DESC
LIMIT 100

UNION ALL

SELECT NULL::int          AS UserId,
       'TOTAL'             AS DisplayName,
       SUM(Reputation)     AS Reputation,
       SUM(QuestionCount) AS QuestionCount,
       SUM(AnswerCount)   AS AnswerCount,
       SUM(QuestionScoreSum) AS QuestionScoreSum,
       SUM(AnswerScoreSum)   AS AnswerScoreSum,
       SUM(GoldBadges)    AS GoldBadges,
       SUM(SilverBadges)  AS SilverBadges,
       SUM(BronzeBadges)  AS BronzeBadges,
       NULL               AS GoldBadgeNames,
       SUM(UpVotesReceived)   AS UpVotesReceived,
       SUM(DownVotesReceived) AS DownVotesReceived,
       SUM(FavoritesReceived) AS FavoritesReceived,
       NULL               AS LastPostDate,
       NULL               AS TopTags
FROM   FinalResult
WHERE  UserId IS NOT NULL;
