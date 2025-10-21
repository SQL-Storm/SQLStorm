-- {"query": "24019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2616} 

WITH
-- Select recent questions
RecentQuestions AS (
    SELECT
        p.Id          AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score       AS QuestionScore,
        p.ViewCount,
        COALESCE(p.AnswerCount,0)   AS AnswerCount,
        COALESCE(p.CommentCount,0)  AS CommentCount,
        COALESCE(p.FavoriteCount,0) AS FavoriteCount,
        p.Tags,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '30 days'
),

-- Count distinct tags per question
TagCountCTE AS (
    SELECT
        r.QuestionId,
        COUNT(DISTINCT trim(both '>'::text from tag)) AS TagCount
    FROM RecentQuestions r
    JOIN LATERAL
        regexp_split_to_table(r.Tags, '</>|<') AS tag
    ON true
    WHERE tag <> ''
    GROUP BY r.QuestionId
),

-- Find duplicates (linktype 3)
DuplicateCTE AS (
    SELECT
        pl.RelatedPostId AS QuestionId,
        pl.PostId        AS DuplicateOf
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),

-- Avg vote score per user
UserAvgVote AS (
    SELECT
        u.Id         AS UserId,
        AVG(v.VoteTypeId) AS AvgVote
    FROM Users u
    LEFT JOIN Votes v
      ON v.UserId = u.Id
    GROUP BY u.Id
),

-- Sum answer scores per question
AnswerScore AS (
    SELECT
        a.ParentId AS QuestionId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END) AS AnswerScore
    FROM Posts a
    JOIN Votes v
      ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),

-- Combine all metrics
Combined AS (
    SELECT
        r.QuestionId,
        r.Title,
        r.CreationDate,
        r.QuestionScore,
        r.ViewCount,
        r.AnswerCount,
        r.CommentCount,
        r.FavoriteCount,
        t.TagCount,
        COALESCE(u.AvgVote,0)                       AS AvgOwnerVote,
        a.AnswerScore,
        d.DuplicateOf,
        COALESCE(r.QuestionScore,0)
        + COALESCE(u.AvgVote,0)
        + COALESCE(a.AnswerScore,0)                AS CombinedScore
    FROM RecentQuestions r
    LEFT JOIN TagCountCTE t
      ON t.QuestionId = r.QuestionId
    LEFT JOIN UserAvgVote u
      ON u.UserId = r.OwnerUserId
    LEFT JOIN AnswerScore a
      ON a.QuestionId = r.QuestionId
    LEFT JOIN DuplicateCTE d
      ON d.QuestionId = r.QuestionId
),

-- Top 50 by view count
TopByViews AS (
    SELECT QuestionId FROM Combined
    ORDER BY ViewCount DESC
    LIMIT 50
),

-- Top 50 by answer count
TopByAnswers AS (
    SELECT QuestionId FROM Combined
    ORDER BY AnswerCount DESC
    LIMIT 50
),

-- Intersection of the two tops
IntersectCTE AS (
    SELECT QuestionId FROM TopByViews
    INTERSECT
    SELECT QuestionId FROM TopByAnswers
),

-- Final set
FinalCte AS (
    SELECT c.*
    FROM Combined c
    WHERE c.QuestionId IN (SELECT QuestionId FROM IntersectCTE)
)

SELECT
    fc.QuestionId,
    fc.Title,
    fc.CombinedScore,
    fc.ViewCount,
    fc.AnswerCount,
    fc.TagCount,
    fc.AvgOwnerVote,
    fc.AnswerScore,
    fc.DuplicateOf,
    ROW_NUMBER() OVER (
        ORDER BY fc.CombinedScore DESC,
                 fc.AnswerCount DESC,
                 fc.ViewCount DESC
    ) AS Rank
FROM FinalCte fc
ORDER BY fc.CombinedScore DESC,
         fc.AnswerCount DESC;
