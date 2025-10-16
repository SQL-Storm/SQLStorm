-- {"query": "9013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3322} 

WITH
-- recent questions exploded by tag
RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
TagExploded AS (
    SELECT
        rq.Id         AS QuestionId,
        UNNEST(string_to_array(substring(rq.Tags,2,length(rq.Tags)-2), '><')) AS TagName
    FROM RecentQuestions rq
),
-- per‐tag aggregates
TagCounts AS (
    SELECT
        te.TagName,
        COUNT(*)            AS QuesCount,
        AVG(rq.ViewCount)   AS AvgViews
    FROM TagExploded te
    JOIN RecentQuestions rq ON rq.Id = te.QuestionId
    GROUP BY te.TagName
    HAVING COUNT(*) > 5
),
-- filter top tags by view threshold
TopTags AS (
    SELECT
        TagName,
        QuesCount,
        AvgViews,
        ROW_NUMBER() OVER (ORDER BY QuesCount DESC, AvgViews DESC) AS TagRank
    FROM TagCounts
    WHERE AvgViews > (SELECT AVG(AvgViews) FROM TagCounts)
),
-- classify active users
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        CASE
            WHEN u.Reputation >= 100000 THEN 'Legend'
            WHEN u.Reputation >= 10000  THEN 'Expert'
            ELSE 'Contributor'
        END AS UserClass
    FROM Users u
    WHERE u.LastAccessDate >= NOW() - INTERVAL '1 year'
),
-- answer‐level stats per question
AnswerStats AS (
    SELECT
        q.Id                  AS QuestionId,
        COUNT(a.Id)           AS AnswerCount,
        MAX(a.Score)          AS MaxAnswerScore,
        SUM(CASE WHEN a.Score < 0 THEN 1 ELSE 0 END) AS NegativeAnswers
    FROM Posts q
    LEFT JOIN Posts a
      ON a.ParentId = q.Id
     AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
-- demonstrate set operators: rich vs. poor questions, excluding gold‐badged owners
SetOps AS (
    SELECT
        q.Id      AS QuestionId,
        'Rich'    AS Category
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.ViewCount > 1000

    UNION

    SELECT
        q.Id,
        'Poor'
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.ViewCount < 100

    EXCEPT

    SELECT
        q.Id,
        CASE WHEN b.Class = 1 THEN 'Rich' ELSE 'Poor' END
    FROM Posts q
    JOIN Badges b
      ON b.UserId = q.OwnerUserId
    WHERE q.PostTypeId = 1
      AND b.Class = 1
),
-- questions closed in last month
ClosedQuestions AS (
    SELECT DISTINCT ph.PostId AS QuestionId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10  -- Post Closed
      AND ph.CreationDate >= NOW() - INTERVAL '1 month'
)
SELECT
    tt.TagName,
    tt.QuesCount,
    ROUND(tt.AvgViews)::INT AS AvgViews,
    tt.TagRank,
    ua.UserClass,
    ua.DisplayName AS TopUser,
    a.MaxAnswerScore,
    a.NegativeAnswers,
    so.Category    AS RichOrPoor,
    COALESCE(cq.QuestionId, -1) AS RecentlyClosed
FROM TopTags tt
-- per‐tag lateral subquery for top answerer by reputation
LEFT JOIN LATERAL (
    SELECT u2.Id, u2.DisplayName, u2.Reputation
    FROM Posts p2
    JOIN Users u2 ON u2.Id = p2.OwnerUserId
    WHERE p2.PostTypeId = 1
      AND POSITION('<'||tt.TagName||'>' IN p2.Tags) > 0
    ORDER BY u2.Reputation DESC
    LIMIT 1
) AS ua ON TRUE
JOIN UserActivity ua2
  ON ua2.Id = ua.Id
JOIN AnswerStats a
  ON a.QuestionId IN (
         SELECT QuestionId
         FROM TagExploded te
         WHERE te.TagName = tt.TagName
     )
LEFT JOIN SetOps so
  ON so.QuestionId IN (
         SELECT QuestionId
         FROM TagExploded te
         WHERE te.TagName = tt.TagName
     )
LEFT JOIN ClosedQuestions cq
  ON cq.QuestionId IN (
         SELECT QuestionId
         FROM TagExploded te
         WHERE te.TagName = tt.TagName
     )

INTERSECT

SELECT
    tt2.TagName,
    tt2.QuesCount,
    ROUND(tt2.AvgViews)::INT,
    tt2.TagRank,
    NULL::varchar,    -- no user class
    NULL::varchar,    -- no top user
    NULL::int,        -- no answer stats
    NULL::int,
    NULL::varchar,
    NULL::int
FROM TopTags tt2
WHERE tt2.TagRank <= 3

ORDER BY AvgViews DESC, QuesCount DESC;
