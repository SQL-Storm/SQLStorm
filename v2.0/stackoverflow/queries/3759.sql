-- {"query": "3759.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2315} 
WITH UserStats AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)       AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)       AS AnswerCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
        MAX(p.LastActivityDate)                           AS LastPostActivity,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

TagAgg AS (
    SELECT
        u.Id                                    AS UserId,
        t.TagName,
        COUNT(*)                                AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p
         ON p.OwnerUserId = u.Id
        AND p.PostTypeId = 1
        AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT trim(both '<>' FROM regexp_split_to_table(p.Tags, '><')) AS TagName
    ) AS split_tag
    JOIN Tags t
         ON t.TagName = split_tag.TagName
    GROUP BY u.Id, t.TagName
),

RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVoteCount,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVoteCount,
        MAX(v.CreationDate)                         AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt
         ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    GROUP BY v.UserId
)

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.QuestionCount,
    us.AnswerCount,
    us.HasAcceptedAnswer,
    us.AvgPostScore,
    us.LastPostActivity,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    rv.UpVoteCount,
    rv.DownVoteCount,
    rv.LastVoteDate,
    COALESCE(t.TagName, 'None')          AS TopTag,
    COALESCE(t.TagUseCount,0)            AS TopTagUseCount
FROM UserStats us
LEFT JOIN RecentVotes rv
       ON rv.UserId = us.UserId
LEFT JOIN (
    SELECT UserId, TagName, TagUseCount
    FROM TagAgg
    WHERE TagRank = 1
) t
       ON t.UserId = us.UserId
WHERE (us.Reputation > 10000 OR us.GoldBadges >= 1)
  AND (us.LastPostActivity IS NULL OR us.LastPostActivity > '2021-01-01')

UNION ALL

SELECT
    NULL                               AS UserId,
    'Aggregate Summary'                AS DisplayName,
    SUM(us.Reputation)                 AS Reputation,
    SUM(us.NetVotes)                   AS NetVotes,
    SUM(us.QuestionCount)              AS QuestionCount,
    SUM(us.AnswerCount)                AS AnswerCount,
    SUM(us.HasAcceptedAnswer)          AS HasAcceptedAnswer,
    AVG(us.AvgPostScore)               AS AvgPostScore,
    MAX(us.LastPostActivity)           AS LastPostActivity,
    SUM(us.GoldBadges)                 AS GoldBadges,
    SUM(us.SilverBadges)               AS SilverBadges,
    SUM(us.BronzeBadges)               AS BronzeBadges,
    SUM(COALESCE(rv.UpVoteCount,0))    AS UpVoteCount,
    SUM(COALESCE(rv.DownVoteCount,0))  AS DownVoteCount,
    MAX(rv.LastVoteDate)               AS LastVoteDate,
    NULL                               AS TopTag,
    NULL                               AS TopTagUseCount
FROM UserStats us
LEFT JOIN RecentVotes rv
       ON rv.UserId = us.UserId
WHERE us.Reputation IS NOT NULL
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;