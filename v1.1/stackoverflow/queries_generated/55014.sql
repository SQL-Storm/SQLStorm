-- {"query": "55014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1782} 

WITH TagStats AS (
    SELECT
        t.Id                                    AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1)                         AS QuestionCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)                                 AS AvgQuestionScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1)                             AS TotalQuestionViews,
        COUNT(a.Id)                                                                  AS AnswerCount,
        AVG(a.Score)                                                                 AS AvgAnswerScore,
        MAX(p.CreationDate)                                                         AS MostRecentQuestion
    FROM Tags t
    JOIN Posts p
        ON p.PostTypeId = 1
       AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN Posts a
        ON a.ParentId = p.Id
       AND a.PostTypeId = 2
    GROUP BY t.Id, t.TagName
),

UserActivity AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6))     AS EditCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2)                    AS UpvoteGiven,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3)                    AS DownvoteGiven,
        COUNT(DISTINCT b.Id)                                                   AS BadgeCount
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Votes v        ON v.UserId = u.Id
    LEFT JOIN Badges b       ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

TopTagContributors AS (
    SELECT
        ts.TagId,
        ts.TagName,
        u.Id                                 AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)          AS AnswersGiven,
        ROW_NUMBER() OVER (PARTITION BY ts.TagId ORDER BY COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) DESC) AS rn
    FROM TagStats ts
    JOIN Posts p
        ON p.Tags LIKE '%' || '<' || ts.TagName || '>' || '%'
    JOIN Users u
        ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
    GROUP BY ts.TagId, ts.TagName, u.Id, u.DisplayName
)

SELECT
    ts.TagName,
    ts.QuestionCount,
    ts.AnswerCount,
    ts.AvgQuestionScore,
    ts.AvgAnswerScore,
    ts.TotalQuestionViews,
    ts.MostRecentQuestion,
    ua.DisplayName   AS TopEditor,
    ua.EditCount,
    ua.UpvoteGiven,
    ua.DownvoteGiven,
    ua.BadgeCount,
    ttc.DisplayName  AS TopAnswerer,
    ttc.AnswersGiven
FROM TagStats ts
LEFT JOIN LATERAL (
    SELECT
        ua2.DisplayName,
        ua2.EditCount,
        ua2.UpvoteGiven,
        ua2.DownvoteGiven,
        ua2.BadgeCount
    FROM UserActivity ua2
    ORDER BY ua2.EditCount DESC, ua2.BadgeCount DESC
    LIMIT 1
) ua ON TRUE
LEFT JOIN LATERAL (
    SELECT
        ttc2.DisplayName,
        ttc2.AnswersGiven
    FROM TopTagContributors ttc2
    WHERE ttc2.TagId = ts.TagId
      AND ttc2.rn = 1
) ttc ON TRUE
ORDER BY ts.QuestionCount DESC
LIMIT 100;
