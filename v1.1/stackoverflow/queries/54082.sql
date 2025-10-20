-- {"query": "54082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1794} 
WITH user_posts AS (
    SELECT
        u.Id          AS UserId,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)   AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)   AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)  AS AvgQuestionScore,
        MIN(p.CreationDate)                          AS FirstPostDate,
        MAX(p.CreationDate)                          AS LastPostDate
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.Reputation
),
user_comments AS (
    SELECT
        UserId,
        COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
),
tagged_questions AS (
    SELECT
        p.Id,
        p.Tags,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_split AS (
    SELECT
        tq.OwnerUserId,
        TRIM(BOTH '<>' FROM g.tag) AS Tag
    FROM tagged_questions tq,
         LATERAL unnest(string_to_array(regexp_replace(tq.Tags, '^<|>$','','g'), '><')) AS g(tag)
),
tag_counts AS (
    SELECT
        OwnerUserId,
        Tag,
        COUNT(*) AS TagFreq
    FROM tag_split
    GROUP BY OwnerUserId, Tag
),
top_tags AS (
    SELECT
        OwnerUserId,
        Tag,
        TagFreq,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagFreq DESC, Tag) AS rn
    FROM tag_counts
),
bids AS (
    SELECT
        p.OwnerUserId,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS HighestBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
    GROUP BY p.OwnerUserId
)
SELECT
    up.UserId,
    up.Reputation,
    up.QuestionCount,
    up.AnswerCount,
    up.AvgQuestionScore,
    up.FirstPostDate,
    up.LastPostDate,
    COALESCE(mc.CommentCount, 0)                AS CommentCount,
    COALESCE(tt.Tag, 'None')                    AS TopTag,
    COALESCE(b.HighestBounty, 0)                AS HighestBounty,
    EXTRACT(DAY FROM up.LastPostDate - up.FirstPostDate) AS ActivePeriodDays
FROM user_posts up
LEFT JOIN user_comments mc ON mc.UserId = up.UserId
LEFT JOIN top_tags tt ON tt.OwnerUserId = up.UserId AND tt.rn = 1
LEFT JOIN bids b ON b.OwnerUserId = up.UserId
WHERE up.QuestionCount > 0
ORDER BY up.Reputation DESC
LIMIT 100;