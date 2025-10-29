WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        MAX(p.LastActivityDate) AS LastActivity,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedCount
    FROM Users u
    LEFT JOIN Badges b          ON b.UserId = u.Id
    LEFT JOIN Posts p           ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph    ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TopUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.TotalPostScore,
        us.QuestionCount,
        us.AnswerCount,
        us.LastActivity,
        us.ClosedCount,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.GoldBadges DESC, us.TotalPostScore DESC) AS RankByReputation
    FROM UserStats us
    WHERE us.Reputation > 10000
),

RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END)      AS UpVotesGiven,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END)    AS DownVotesGiven,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END)   AS FavoritesGiven,
        MAX(v.CreationDate)                                AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    GROUP BY v.UserId
),

UserTagStats AS (
    SELECT
        pu.Id               AS UserId,
        t.TagName,
        COUNT(*)            AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY pu.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    JOIN Users pu               ON pu.Id = p.OwnerUserId
    JOIN LATERAL unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tg(tag) ON true
    JOIN Tags t                 ON t.TagName = tg.tag
    WHERE p.PostTypeId = 1
    GROUP BY pu.Id, t.TagName
),

TopUserTags AS (
    SELECT UserId, TagName, TagUseCount, TagRank
    FROM UserTagStats
    WHERE TagRank = 1
),

MainResults AS (
    SELECT
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.TotalPostScore,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.ClosedCount,
        tu.LastActivity,
        rv.UpVotesGiven,
        rv.DownVotesGiven,
        rv.FavoritesGiven,
        rv.LastVoteDate,
        CASE WHEN utt.TagRank = 1 THEN utt.TagName END AS TopTag,
        utt.TagUseCount AS TopTagUseCount,
        tu.RankByReputation
    FROM TopUsers tu
    LEFT JOIN RecentVotes rv
           ON rv.UserId = tu.Id
    LEFT JOIN TopUserTags utt
           ON utt.UserId = tu.Id
    WHERE tu.RankByReputation <= 100
)

SELECT *
FROM MainResults
UNION ALL
SELECT
    CAST(NULL AS BIGINT)        AS Id,
    CAST(NULL AS VARCHAR)       AS DisplayName,
    CAST(NULL AS INTEGER)       AS Reputation,
    CAST(NULL AS INTEGER)       AS GoldBadges,
    CAST(NULL AS INTEGER)       AS SilverBadges,
    CAST(NULL AS INTEGER)       AS BronzeBadges,
    CAST(NULL AS BIGINT)        AS TotalPostScore,
    CAST(NULL AS INTEGER)       AS QuestionCount,
    CAST(NULL AS INTEGER)       AS AnswerCount,
    CAST(NULL AS INTEGER)       AS ClosedCount,
    CAST(NULL AS TIMESTAMP)     AS LastActivity,
    CAST(NULL AS INTEGER)       AS UpVotesGiven,
    CAST(NULL AS INTEGER)       AS DownVotesGiven,
    CAST(NULL AS INTEGER)       AS FavoritesGiven,
    CAST(NULL AS TIMESTAMP)     AS LastVoteDate,
    CAST(NULL AS VARCHAR)       AS TopTag,
    CAST(NULL AS INTEGER)       AS TopTagUseCount,
    CAST(NULL AS INTEGER)       AS RankByReputation
ORDER BY RankByReputation
LIMIT 100;