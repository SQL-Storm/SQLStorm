-- {"query": "54063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2115} 
WITH upvotes_by_post AS (
    SELECT
        v.PostId,
        COUNT(*) AS UpVoteCount
    FROM Votes v
    WHERE v.VoteTypeId = 2          -- upvotes
    GROUP BY v.PostId
),
question_tags AS (
    SELECT
        p.Id                     AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1          -- questions only
),
tag_user_stats AS (
    SELECT
        qt.TagName,
        u.Id          AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(*)      AS QuestionCount,
        SUM(qt.Score) AS TotalScore,
        AVG(qt.AnswerCount) AS AvgAnswerCount,
        MIN(qt.CreationDate) AS FirstDate,
        MAX(qt.CreationDate) AS LastDate,
        SUM(coalesce(up.UpVoteCount, 0)) AS TotalUpvotes,
        ROW_NUMBER() OVER (PARTITION BY qt.TagName ORDER BY COUNT(*) DESC) AS rn
    FROM question_tags qt
    JOIN Users u ON qt.OwnerUserId = u.Id
    LEFT JOIN upvotes_by_post up ON up.PostId = qt.PostId
    GROUP BY qt.TagName, u.Id, u.DisplayName, u.Reputation
)
SELECT
    TagName,
    UserId,
    DisplayName,
    Reputation,
    QuestionCount,
    TotalScore,
    AvgAnswerCount,
    FirstDate,
    LastDate,
    TotalUpvotes
FROM tag_user_stats
WHERE rn <= 5
ORDER BY TagName, QuestionCount DESC;