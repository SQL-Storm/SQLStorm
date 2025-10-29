-- {"query": "3335.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3047}
WITH
    UserReputationChanges AS (
        SELECT
            u.Id AS UserId,
            u.Reputation,
            ph.CreationDate,
            LAG(u.Reputation) OVER (PARTITION BY u.Id ORDER BY ph.CreationDate) AS PrevRep,
            (u.Reputation - LAG(u.Reputation) OVER (PARTITION BY u.Id ORDER BY ph.CreationDate)) AS RepDelta
        FROM Users u
        LEFT JOIN PostHistory ph
            ON ph.UserId = u.Id
           AND ph.PostHistoryTypeId = 2
    ),
    TopUserBadges AS (
        SELECT
            b.UserId,
            STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS GoldBadges,
            STRING_AGG(DISTINCT CASE WHEN b.Class = 2 THEN b.Name END, ', ') AS SilverBadges,
            STRING_AGG(DISTINCT CASE WHEN b.Class = 3 THEN b.Name END, ', ') AS BronzeBadges,
            COUNT(*) AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    UserAnswerTagStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            tag.Tag AS Tag,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
        FROM Posts p,
             LATERAL (
               SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><')) AS Tag
             ) tag
        WHERE p.PostTypeId = 2
          AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, tag.Tag
    ),
    UserTagRankings AS (
        SELECT
            uats.UserId,
            uats.Tag,
            uats.AnswerCount,
            uats.AvgAnswerScore,
            ROW_NUMBER() OVER (PARTITION BY uats.UserId
                               ORDER BY uats.AnswerCount DESC, uats.AvgAnswerScore DESC) AS TagRank
        FROM UserAnswerTagStats uats
    ),
    RecentHighScoringPosts AS (
        SELECT
            p.Id,
            p.OwnerUserId,
            p.Title,
            p.Score,
            p.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate >= DATE_TRUNC('year', CAST('2024-10-01' AS DATE)) - INTERVAL '1' YEAR
          AND p.Score > 10
    ),
    UserActivitySummary AS (
        SELECT
            u.Id AS UserId,
            COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
            COALESCE(u.Reputation, 0) AS CurrentReputation,
            COALESCE(b.TotalBadges, 0) AS BadgeCount,
            COALESCE(b.GoldBadges, '') AS GoldBadges,
            COALESCE(b.SilverBadges, '') AS SilverBadges,
            COALESCE(b.BronzeBadges, '') AS BronzeBadges,
            COALESCE(pcnt.PostCount, 0) AS TotalPosts,
            COALESCE(acnt.AnswerCount, 0) AS TotalAnswers,
            COALESCE(vcnt.VoteCount, 0) AS TotalVotesReceived,
            COALESCE(rc.RepDelta, 0) AS LastRepChange
        FROM Users u
        LEFT JOIN (SELECT OwnerUserId, COUNT(*) AS PostCount FROM Posts GROUP BY OwnerUserId) pcnt
            ON pcnt.OwnerUserId = u.Id
        LEFT JOIN (SELECT OwnerUserId, COUNT(*) AS AnswerCount FROM Posts WHERE PostTypeId = 2 GROUP BY OwnerUserId) acnt
            ON acnt.OwnerUserId = u.Id
        LEFT JOIN (SELECT p.OwnerUserId, COUNT(v.Id) AS VoteCount FROM Posts p JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2 GROUP BY p.OwnerUserId) vcnt
            ON vcnt.OwnerUserId = u.Id
        LEFT JOIN TopUserBadges b
            ON b.UserId = u.Id
        LEFT JOIN LATERAL (
            SELECT urc.RepDelta, urc.CreationDate, urc.UserId
            FROM UserReputationChanges urc
            WHERE urc.UserId = u.Id
            ORDER BY urc.CreationDate DESC
            LIMIT 1
        ) rc ON rc.UserId = u.Id
    ),
    FinalResult AS (
        SELECT
            uas.UserId,
            uas.DisplayName,
            uas.CurrentReputation,
            uas.BadgeCount,
            uas.GoldBadges,
            uas.SilverBadges,
            uas.BronzeBadges,
            uas.TotalPosts,
            uas.TotalAnswers,
            uas.TotalVotesReceived,
            uas.LastRepChange,
            tr.Tag AS TopTag,
            tr.AnswerCount AS TopTagAnswerCount,
            tr.AvgAnswerScore AS TopTagAvgScore,
            rp.Title AS RecentHighScorePost,
            rp.Score AS RecentHighScore
        FROM UserActivitySummary uas
        LEFT JOIN UserTagRankings tr
            ON tr.UserId = uas.UserId AND tr.TagRank = 1
        LEFT JOIN RecentHighScoringPosts rp
            ON rp.OwnerUserId = uas.UserId AND rp.rn = 1
    ),
    FilteredFinal AS (
        SELECT *
        FROM FinalResult
        WHERE CurrentReputation > 1000
           OR BadgeCount >= 5
           OR TopTag IS NOT NULL
           OR RecentHighScorePost IS NOT NULL
        ORDER BY CurrentReputation DESC, BadgeCount DESC
        LIMIT 100
    ),
    AggregatedTotals AS (
        SELECT
            NULL::bigint AS UserId,
            'Aggregated Totals' AS DisplayName,
            SUM(CurrentReputation) AS CurrentReputation,
            SUM(BadgeCount) AS BadgeCount,
            NULL::text AS GoldBadges,
            NULL::text AS SilverBadges,
            NULL::text AS BronzeBadges,
            SUM(TotalPosts) AS TotalPosts,
            SUM(TotalAnswers) AS TotalAnswers,
            SUM(TotalVotesReceived) AS TotalVotesReceived,
            NULL::numeric AS LastRepChange,
            NULL::text AS TopTag,
            NULL::bigint AS TopTagAnswerCount,
            NULL::numeric AS TopTagAvgScore,
            NULL::text AS RecentHighScorePost,
            NULL::bigint AS RecentHighScore
        FROM FinalResult
        WHERE CurrentReputation > 0
    )
SELECT *
FROM FilteredFinal

UNION ALL

SELECT *
FROM AggregatedTotals;