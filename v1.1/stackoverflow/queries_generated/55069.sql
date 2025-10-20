-- {"query": "55069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1451} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)            AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)            AS AnswerCount,
        SUM(p.Score)                                          AS TotalScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)          AS AvgQuestionScore,
        COUNT(b.Id)                                           AS BadgeCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)           AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)           AS DownVotesGiven
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId      = u.Id
    LEFT JOIN Votes   v ON v.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TopTags AS (
    SELECT
        pt.OwnerUserId                AS UserId,
        t.TagName,
        COUNT(*)                     AS TagUsage,
        ROW_NUMBER() OVER (PARTITION BY pt.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts pt
    JOIN LATERAL regexp_split_to_table(pt.Tags, '[><]') AS tag_raw(tag)
          ON pt.Tags IS NOT NULL
    JOIN Tags t ON t.TagName = tag_raw.tag
    WHERE pt.PostTypeId = 1
    GROUP BY pt.OwnerUserId, t.TagName
),

UserTagSummary AS (
    SELECT
        UserId,
        array_agg(TagName ORDER BY TagUsage DESC)[:5] AS Top5Tags
    FROM TopTags
    WHERE rn <= 5
    GROUP BY UserId
),

RecentActivity AS (
    SELECT
        u.Id                                    AS UserId,
        MAX(p.CreationDate)                     AS LastPostDate,
        MAX(c.CreationDate)                     AS LastCommentDate,
        GREATEST(
            COALESCE(MAX(p.CreationDate), '1970-01-01'::timestamp),
            COALESCE(MAX(c.CreationDate), '1970-01-01'::timestamp)
        )                                        AS LastActivity
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id
)

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    us.AvgQuestionScore,
    us.BadgeCount,
    us.UpVotesGiven,
    us.DownVotesGiven,
    ut.Top5Tags,
    ra.LastActivity,
    RANK()        OVER (ORDER BY us.Reputation DESC)      AS ReputationRank,
    PERCENT_RANK() OVER (ORDER BY us.TotalScore DESC)    AS ScorePercentile
FROM UserStats      us
LEFT JOIN UserTagSummary   ut ON ut.UserId = us.Id
LEFT JOIN RecentActivity   ra ON ra.UserId = us.Id
WHERE us.Reputation > 1000
ORDER BY us.Reputation DESC
LIMIT 100;
