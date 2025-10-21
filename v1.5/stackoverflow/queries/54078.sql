-- {"query": "54078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2691} 
WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalViews,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedCount,
        MAX(p.Score) AS MaxScore
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
TagStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUBSTRING(t.tag FROM 2 FOR CHAR_LENGTH(t.tag)-2) AS TagName,
        COUNT(*) AS TagCount
    FROM
        Posts p
        CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '><') AS t(tag)
    WHERE
        p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId, TagName
),
TopTag AS (
    SELECT
        ts.UserId,
        ts.TagName,
        ts.TagCount,
        ROW_NUMBER() OVER (PARTITION BY ts.UserId ORDER BY ts.TagCount DESC) AS rn
    FROM
        TagStats ts
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    us.AvgScore,
    us.TotalViews,
    us.BadgeCount,
    us.TotalUpVotes,
    us.TotalDownVotes,
    us.AcceptedCount,
    us.MaxScore,
    tt.TagName      AS TopTag,
    tt.TagCount     AS TopTagCount
FROM
    UserStats us
    LEFT JOIN TopTag tt ON tt.UserId = us.UserId AND tt.rn = 1
ORDER BY
    us.Reputation DESC,
    us.TotalPosts DESC
LIMIT 200;