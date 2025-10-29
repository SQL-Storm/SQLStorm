-- {"query": "3400.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2348} 

WITH
/* Aggregate statistics per tag for questions */
TagStats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                              AS QuestionCount,
        SUM(p.Score)                             AS TotalScore,
        AVG(p.ViewCount)                         AS AvgViews,
        MAX(p.CreationDate)                      AS MostRecentQuestion
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE ('%<'||t.TagName||'>%')
    WHERE p.PostTypeId = 1               -- only questions
    GROUP BY t.TagName
),

/* Activity summary per user */
UserActivity AS (
    SELECT
        u.Id                                            AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END),0) AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END),0) AS DownVotesGiven,
        COALESCE(COUNT(DISTINCT c.Id),0)                AS CommentsMade,
        MAX(p.CreationDate)                            AS LastPostDate
    FROM Users u
    LEFT JOIN Votes     v ON v.UserId = u.Id
    LEFT JOIN Comments  c ON c.UserId = u.Id
    LEFT JOIN Posts     p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

/* Core metrics per question, with window functions */
PostMetrics AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(v.UpVotes,0)      AS UpVotes,
        COALESCE(v.DownVotes,0)    AS DownVotes,
        COALESCE(c.CommentCount,0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankByScore,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END               AS IsClosed,
        (SELECT MIN(ph.CreationDate)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
           AND ph.PostHistoryTypeId IN (4,5,6))                           AS FirstEditDate
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1               -- questions only
),

/* Limited set of prolific tags */
TopTags AS (
    SELECT TagName
    FROM TagStats
    WHERE QuestionCount > 1000
    ORDER BY TotalScore DESC
    LIMIT 10
)

/* Final result set combining everything */
SELECT
    pm.Id,
    pm.Title,
    pm.CreationDate,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.UpVotes,
    pm.DownVotes,
    pm.CommentCount,
    pm.RankByScore,
    pm.IsClosed,
    pm.FirstEditDate,
    ua.DisplayName          AS OwnerDisplayName,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.CommentsMade,
    ua.LastPostDate,
    tg.TagName,
    COALESCE(ts.QuestionCount,0) AS TagQuestionCount,
    COALESCE(ts.TotalScore,0)    AS TagTotalScore
FROM PostMetrics pm
LEFT JOIN Users u ON u.Id = pm.Id                              -- intentional mismatch to produce NULLs
LEFT JOIN UserActivity ua ON ua.UserId = u.Id
LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(pm.Title,2,length(pm.Title)-2), '><')) AS TagName
) tg ON true
LEFT JOIN TagStats ts ON ts.TagName = tg.TagName
WHERE pm.RankByScore <= 5
  AND (ua.UpVotesGiven > 100 OR ua.DownVotesGiven IS NULL)
  AND EXISTS (
        SELECT 1
        FROM PostLinks pl
        WHERE pl.PostId = pm.Id
          AND pl.LinkTypeId = 3                               -- duplicate link
          AND pl.RelatedPostId IN (
                SELECT Id FROM Posts WHERE Score > 50
          )
  )
  AND (pm.IsClosed = 0 OR pm.FirstEditDate IS NOT NULL)

UNION ALL

/* Additional slice: low‑scoring answers without up‑votes */
SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM Posts p
WHERE p.PostTypeId = 2                 -- answers
  AND p.Score < 0
  AND NOT EXISTS (
        SELECT 1 FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2   -- no up‑votes
  )
ORDER BY CreationDate DESC
LIMIT 50;
