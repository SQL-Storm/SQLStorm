-- {"query": "9007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 2839} 

WITH ActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id)                                    AS QuestionCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END)
                                                                AS UpvoteSum,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS rn_rep
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
       AND p.PostTypeId    = 1
    LEFT JOIN Votes v
        ON v.UserId = u.Id
       AND v.VoteTypeId IN (2,3)
    WHERE u.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)           AS AvgQScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)           AS AvgAScore
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
),
TopAnswerers AS (
    SELECT
        a.OwnerUserId                AS UserId,
        COUNT(*)                     AS AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
PopularTags AS (
    SELECT t.TagName
    FROM Tags t
    WHERE t.Count > 10000
    INTERSECT
    SELECT ts.TagName
    FROM TagStats ts
    WHERE ts.Questions > 100
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY b.UserId
),
Commenters AS (
    SELECT
        c.UserId,
        COUNT(*) AS CommentCount
    FROM Comments c
    JOIN Posts p ON p.Id = c.PostId
    WHERE p.Score > (SELECT AVG(p2.Score) FROM Posts p2)
    GROUP BY c.UserId
)
SELECT
    au.DisplayName,
    au.QuestionCount,
    au.UpvoteSum,
    COALESCE(ts.Questions,0) || ' / ' || COALESCE(ts.Answers,0)     AS QnA_Ratio,
    ROUND(COALESCE(ts.AvgQScore,0),2)                              AS AvgQScore,
    ROUND(COALESCE(ts.AvgAScore,0),2)                              AS AvgAScore,
    COALESCE(bs.BadgeCount,0)                                      AS BadgeCount,
    COALESCE(cm.CommentCount,0)                                    AS CommentCount,
    pt.TagName                                                     AS PopularTag,
    ta.AnswerCount
FROM ActiveUsers au
FULL OUTER JOIN TagStats ts
    ON ts.TagName = (
        SELECT split_part(split_part(p.Tags, '<', 2), '>', 1)
        FROM Posts p
        WHERE p.OwnerUserId = au.Id
          AND p.PostTypeId   = 1
        ORDER BY p.ViewCount DESC
        LIMIT 1
    )
LEFT JOIN BadgeSummary bs
    ON bs.UserId = au.Id
LEFT JOIN Commenters cm
    ON cm.UserId = au.Id
LEFT JOIN PopularTags pt
    ON pt.TagName = ts.TagName
LEFT JOIN TopAnswerers ta
    ON ta.UserId = au.Id
   AND ta.rn    = 1
WHERE au.UpvoteSum > (SELECT AVG(UpvoteSum) FROM ActiveUsers)
  AND COALESCE(ts.Questions,0) > 10
ORDER BY au.QuestionCount DESC, au.UpvoteSum DESC
LIMIT 100

UNION ALL

SELECT
    'TOTAL'       AS DisplayName,
    COUNT(*)      AS QuestionCount,
    NULL          AS UpvoteSum,
    NULL          AS QnA_Ratio,
    NULL          AS AvgQScore,
    NULL          AS AvgAScore,
    NULL          AS BadgeCount,
    NULL          AS CommentCount,
    NULL          AS PopularTag,
    NULL          AS AnswerCount
FROM ActiveUsers;
