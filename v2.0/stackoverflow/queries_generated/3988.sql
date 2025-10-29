-- {"query": "3988.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2179} 

WITH BadgeAgg AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount,
        COUNT(*)                                        AS TotalBadges
    FROM Badges
    GROUP BY UserId
),

PostAgg AS (
    SELECT 
        OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE PostTypeId = 1)                AS QuestionCount,
        COUNT(*) FILTER (WHERE PostTypeId = 2)                AS AnswerCount,
        AVG(Score) FILTER (WHERE Score IS NOT NULL)          AS AvgScore,
        SUM(ViewCount)                                       AS TotalViews,
        MAX(LastActivityDate)                                AS LastPostActivity
    FROM Posts
    GROUP BY OwnerUserId
),

VoteAgg AS (
    SELECT 
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)    AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)    AS DownVoteCount,
        MAX(v.CreationDate)                                 AS LastVoteDate
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),

TagExplode AS (
    SELECT 
        p.OwnerUserId AS UserId,
        LOWER(TRIM(t)) AS Tag
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(
                   substring(p.Tags FROM '^<(.+)>$'), 
                   '><'
               ) AS t
    ) sub
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),

TagFreq AS (
    SELECT 
        UserId,
        Tag,
        COUNT(*) AS TagCnt,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(*) DESC, Tag) AS rn
    FROM TagExplode
    GROUP BY UserId, Tag
),

RecentActivity AS (
    SELECT 
        UserId,
        MAX(ActivityDate) AS RecentDate
    FROM (
        SELECT OwnerUserId AS UserId, LastActivityDate AS ActivityDate FROM Posts
        UNION ALL
        SELECT UserId, CreationDate FROM Comments
        UNION ALL
        SELECT UserId, CreationDate FROM Votes
    ) a
    GROUP BY UserId
)

SELECT 
    u.Id                                 AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(b.GoldCount,   0)           AS GoldBadges,
    COALESCE(b.SilverCount, 0)           AS SilverBadges,
    COALESCE(b.BronzeCount, 0)           AS BronzeBadges,
    COALESCE(p.QuestionCount, 0)         AS Questions,
    COALESCE(p.AnswerCount,   0)         AS Answers,
    ROUND(COALESCE(p.AvgScore, 0)::numeric, 2) AS AvgPostScore,
    COALESCE(v.UpVoteCount, 0) - COALESCE(v.DownVoteCount, 0) AS NetVotes,
    COALESCE(p.TotalViews, 0)            AS Views,
    COALESCE(r.RecentDate,
             GREATEST(
                 COALESCE(p.LastPostActivity,   TIMESTAMP '1970-01-01'),
                 COALESCE(v.LastVoteDate,      TIMESTAMP '1970-01-01')
             )
    )                                   AS LastActivity,
    tf.Tag                               AS TopTag,
    tf.TagCnt                            AS TopTagCount
FROM Users u
LEFT JOIN BadgeAgg      b  ON b.UserId = u.Id
LEFT JOIN PostAgg       p  ON p.UserId = u.Id
LEFT JOIN VoteAgg       v  ON v.UserId = u.Id
LEFT JOIN RecentActivity r  ON r.UserId = u.Id
LEFT JOIN (
    SELECT UserId, Tag, TagCnt
    FROM TagFreq
    WHERE rn = 1
) tf ON tf.UserId = u.Id
WHERE u.Reputation > 1000
ORDER BY u.Reputation DESC, LastActivity DESC
LIMIT 100;
