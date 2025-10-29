-- {"query": "3783.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1631}
WITH
recent_q AS (
    SELECT
        p.Id                                 AS QId,
        p.Title,
        p.CreationDate,
        p.Score                              AS QScore,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(NULLIF(p.Tags, ''), '<null>') AS RawTags,
        regexp_split_to_table(p.Tags, '[><]') AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
),
tag_stats AS (
    SELECT
        tag          AS TagName,
        COUNT(*)     AS QCount,
        SUM(q.QScore)          AS SumScore,
        AVG(q.QScore)          AS AvgScore,
        MAX(q.CreationDate)    AS LatestQDate
    FROM recent_q q
    GROUP BY tag
),
user_activity AS (
    SELECT
        u.Id                                  AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id)                 AS RecentPosts,
        COUNT(DISTINCT v.Id)                 AS RecentVotes,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(p.CreationDate)                 AS LastPostDate,
        MAX(v.CreationDate)                  AS LastVoteDate
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
          AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
    LEFT JOIN Votes v
           ON v.UserId = u.Id
          AND v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
    LEFT JOIN Badges b
           ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
answer_perf AS (
    SELECT
        q.Id                                 AS QId,
        COUNT(a.Id)                          AS AnswerCnt,
        AVG(a.Score)                         AS AvgAnswerScore,
        MAX(a.Score)                         AS MaxAnswerScore,
        MIN(a.CreationDate)                  AS FirstAnswerDate,
        MAX(a.CreationDate)                  AS LastAnswerDate,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAccepted
    FROM Posts q
    LEFT JOIN Posts a
           ON a.ParentId = q.Id
          AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
question_detail AS (
    SELECT
        q.QId,
        q.Title,
        q.CreationDate,
        q.QScore,
        q.ViewCount,
        q.AnswerCount,
        ts.TagName,
        ts.QCount            AS TagQCount,
        ts.AvgScore          AS TagAvgScore,
        ap.AnswerCnt,
        ap.AvgAnswerScore,
        ap.MaxAnswerScore,
        ap.HasAccepted,
        ROW_NUMBER() OVER (PARTITION BY q.QId ORDER BY ts.TagName) AS TagRank
    FROM recent_q q
    LEFT JOIN tag_stats ts
           ON ts.TagName = q.Tag
    LEFT JOIN answer_perf ap
           ON ap.QId = q.QId
),
user_ranking AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.RecentPosts,
        ua.RecentVotes,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.LastPostDate,
        ua.LastVoteDate,
        RANK() OVER (ORDER BY (ua.Reputation + ua.GoldBadges*1000
                               + ua.SilverBadges*500
                               + ua.BronzeBadges*100
                               + ua.RecentPosts*10
                               + ua.RecentVotes) DESC) AS ActivityRank
    FROM user_activity ua
),
post_without_vote AS (
    SELECT ua.UserId FROM user_activity ua WHERE ua.RecentPosts > 0 AND ua.RecentVotes = 0
),
vote_without_post AS (
    SELECT ua.UserId FROM user_activity ua WHERE ua.RecentVotes > 0 AND ua.RecentPosts = 0
),
user_exclusive AS (
    SELECT * FROM post_without_vote
    UNION ALL
    SELECT * FROM vote_without_post
)
SELECT
    qd.QId,
    qd.Title,
    qd.CreationDate,
    qd.QScore,
    qd.ViewCount,
    qd.AnswerCount,
    qd.TagName,
    qd.TagQCount,
    ROUND(qd.TagAvgScore,2)               AS TagAvgScore,
    qd.AnswerCnt,
    ROUND(qd.AvgAnswerScore,2)            AS AvgAnswerScore,
    qd.MaxAnswerScore,
    CASE WHEN qd.HasAccepted = 1 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer,
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.RecentPosts,
    ur.RecentVotes,
    ur.ActivityRank,
    CASE WHEN ue.UserId IS NOT NULL THEN 1 ELSE 0 END AS IsInExclusiveSet
FROM question_detail qd
LEFT JOIN user_ranking ur
       ON ur.UserId = (
            SELECT p.OwnerUserId
            FROM Posts p
            WHERE p.Id = qd.QId
              AND p.OwnerUserId IS NOT NULL
            LIMIT 1
          )
LEFT JOIN user_exclusive ue
       ON ue.UserId = ur.UserId
WHERE qd.TagRank = 1
ORDER BY qd.CreationDate DESC, ur.ActivityRank ASC
LIMIT 500;