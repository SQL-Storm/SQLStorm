WITH
RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
TagExploded AS (
    SELECT
        rq.Id         AS QuestionId,
        UNNEST(string_to_array(SUBSTRING(rq.Tags, 2, length(rq.Tags) - 2), '><')) AS TagName
    FROM RecentQuestions rq
),
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
TopTags AS (
    SELECT
        TagName,
        QuesCount,
        AvgViews,
        ROW_NUMBER() OVER (ORDER BY QuesCount DESC, AvgViews DESC) AS TagRank
    FROM TagCounts
    WHERE AvgViews > (SELECT AVG(AvgViews) FROM TagCounts)
),
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
    WHERE u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
),
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
ClosedQuestions AS (
    SELECT DISTINCT ph.PostId AS QuestionId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' MONTH
),
TopUsersPerTag AS (
    -- replace LATERAL: find top user per tag by reputation among posts having the tag
    SELECT
        tt.TagName,
        u2.Id AS UserId,
        u2.DisplayName,
        u2.Reputation,
        ROW_NUMBER() OVER (PARTITION BY tt.TagName ORDER BY u2.Reputation DESC) AS rn
    FROM TopTags tt
    JOIN Posts p2
      ON POSITION('<' || tt.TagName || '>' IN p2.Tags) > 0
     AND p2.PostTypeId = 1
    JOIN Users u2
      ON u2.Id = p2.OwnerUserId
)
SELECT
    tt.TagName,
    tt.QuesCount,
    CAST(ROUND(tt.AvgViews) AS INT) AS AvgViews,
    tt.TagRank,
    ua2.UserClass,
    ua2.DisplayName AS TopUser,
    a.MaxAnswerScore,
    a.NegativeAnswers,
    so.Category    AS RichOrPoor,
    COALESCE(cq.QuestionId, -1) AS RecentlyClosed
FROM TopTags tt
LEFT JOIN (
    SELECT TagName, UserId, DisplayName
    FROM TopUsersPerTag
    WHERE rn = 1
) ua ON ua.TagName = tt.TagName
LEFT JOIN UserActivity ua2
  ON ua2.Id = ua.UserId
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
    CAST(ROUND(tt2.AvgViews) AS INT) AS AvgViews,
    tt2.TagRank,
    CAST(NULL AS VARCHAR) AS UserClass,
    CAST(NULL AS VARCHAR) AS TopUser,
    CAST(NULL AS INT) AS MaxAnswerScore,
    CAST(NULL AS INT) AS NegativeAnswers,
    CAST(NULL AS VARCHAR) AS RichOrPoor,
    CAST(NULL AS INT) AS RecentlyClosed
FROM TopTags tt2
WHERE tt2.TagRank <= 3

ORDER BY AvgViews DESC, QuesCount DESC;