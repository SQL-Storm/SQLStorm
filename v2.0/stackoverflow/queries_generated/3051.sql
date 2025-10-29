-- {"query": "3051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2539} 

WITH
    TopReputation AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.Location, 'Unknown') AS Location,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
        FROM Users u
        WHERE u.Reputation IS NOT NULL
    ),
    BadgeAgg AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount,
            COUNT(*)                                                 AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    PostAgg AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)                AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)                AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)        AS AvgScore,
            MAX(p.CreationDate)                                    AS LastPostDate
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    RecentCloseVotes AS (
        SELECT
            ph.UserId,
            COUNT(*)                                   AS CloseVoteCount,
            MAX(ph.CreationDate)                       AS LastCloseVoteDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
        GROUP BY ph.UserId
    ),
    TagMention AS (
        SELECT
            p.OwnerUserId AS UserId,
            SUM(
                CASE
                    WHEN p.Tags IS NULL THEN 0
                    ELSE (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '<c#>', ''))) / LENGTH('<c#>')
                END
            ) AS CSharpTagMentions
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    )
SELECT
    tr.Id,
    tr.DisplayName,
    tr.Reputation,
    tr.RepRank,
    COALESCE(b.GoldCount, 0)       AS GoldBadges,
    COALESCE(b.SilverCount, 0)     AS SilverBadges,
    COALESCE(b.BronzeCount, 0)     AS BronzeBadges,
    COALESCE(pa.QuestionCount, 0)  AS Questions,
    COALESCE(pa.AnswerCount, 0)    AS Answers,
    ROUND(COALESCE(pa.AvgScore, 0), 2) AS AvgPostScore,
    COALESCE(rc.CloseVoteCount, 0) AS CloseVotesReceived,
    rc.LastCloseVoteDate          AS LastCloseVote,
    COALESCE(tm.CSharpTagMentions, 0) AS CSharpTagMentions,
    CASE
        WHEN COALESCE(b.GoldCount, 0) > 0 AND tr.Reputation < 100 THEN 'GoldBadgeLowRep'
        WHEN tr.Reputation >= 20000                                 THEN 'HighRep'
        ELSE                                                         'Normal'
    END AS UserSegment,
    tr.Location
FROM TopReputation tr
LEFT JOIN BadgeAgg       b  ON b.UserId = tr.Id
LEFT JOIN PostAgg        pa ON pa.UserId = tr.Id
LEFT JOIN RecentCloseVotes rc ON rc.UserId = tr.Id
LEFT JOIN TagMention     tm ON tm.UserId = tr.Id
WHERE tr.RepRank <= 50

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    NULL                         AS RepRank,
    COALESCE(b.GoldCount, 0)     AS GoldBadges,
    COALESCE(b.SilverCount, 0)   AS SilverBadges,
    COALESCE(b.BronzeCount, 0)   AS BronzeBadges,
    COALESCE(pa.QuestionCount, 0) AS Questions,
    COALESCE(pa.AnswerCount, 0)   AS Answers,
    ROUND(COALESCE(pa.AvgScore, 0), 2) AS AvgPostScore,
    COALESCE(rc.CloseVoteCount, 0)     AS CloseVotesReceived,
    rc.LastCloseVoteDate               AS LastCloseVote,
    COALESCE(tm.CSharpTagMentions, 0)  AS CSharpTagMentions,
    'GoldBadgeOnly'                    AS UserSegment,
    COALESCE(u.Location, 'Unknown')    AS Location
FROM Users u
LEFT JOIN BadgeAgg       b  ON b.UserId = u.Id
LEFT JOIN PostAgg        pa ON pa.UserId = u.Id
LEFT JOIN RecentCloseVotes rc ON rc.UserId = u.Id
LEFT JOIN TagMention     tm ON tm.UserId = u.Id
WHERE b.GoldCount > 0
  AND (u.Reputation IS NULL OR u.Reputation < 100)
  AND NOT EXISTS (SELECT 1 FROM TopReputation tr WHERE tr.Id = u.Id)

ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
