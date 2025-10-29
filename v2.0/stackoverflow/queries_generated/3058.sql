-- {"query": "3058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1919} 

WITH
    -- Per‑user activity metrics
    UserStats AS (
        SELECT
            u.Id                                   AS UserId,
            u.DisplayName,
            COALESCE(u.Reputation, 0)              AS Reputation,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
            MAX(p.CreationDate)                   AS LastPostDate,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COALESCE(p.CreationDate, '1900-01-01') DESC) AS rn
        FROM Users u
        LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v      ON v.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    -- Tag popularity and edit activity
    TagStats AS (
        SELECT
            t.Id                                 AS TagId,
            t.TagName,
            t.Count                              AS TagUseCount,
            COUNT(DISTINCT ph.PostId) FILTER (WHERE ph.PostHistoryTypeId = 5) AS EditCount,
            STRING_AGG(DISTINCT COALESCE(p.Title, ''), ', ') FILTER (WHERE p.Title IS NOT NULL) AS SampleTitles,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
        FROM Tags t
        LEFT JOIN PostHistory ph ON ph.PostId = t.ExcerptPostId OR ph.PostId = t.WikiPostId
        LEFT JOIN Posts p       ON p.Id = ph.PostId
        GROUP BY t.Id, t.TagName, t.Count
    ),

    -- Recent closed questions with link‑type information
    RecentClosedQuestions AS (
        SELECT
            p.Id,
            p.Title,
            p.CreationDate,
            ph.CreationDate                               AS ClosedDate,
            COALESCE(NULLIF(ph.Comment, ''), 'No reason') AS CloseReason,
            ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE lt.Name IS NOT NULL) AS LinkTypeNames,
            ROW_NUMBER() OVER (ORDER BY ph.CreationDate DESC) AS rn
        FROM Posts p
        JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        LEFT JOIN PostLinks pl ON pl.PostId = p.Id
        LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
        WHERE p.PostTypeId = 1
        GROUP BY p.Id, p.Title, p.CreationDate, ph.CreationDate, ph.Comment
    )

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.UpVotesGiven,
    us.DownVotesGiven,
    us.LastPostDate,
    ts.TagId,
    ts.TagName,
    ts.TagUseCount,
    ts.TagRank,
    rcq.Title          AS RecentClosedTitle,
    rcq.ClosedDate,
    rcq.CloseReason,
    rcq.LinkTypeNames
FROM UserStats us
LEFT JOIN TagStats ts
       ON ts.TagRank = (us.rn % 10) + 1                -- map users onto top‑10 tags
LEFT JOIN RecentClosedQuestions rcq
       ON rcq.rn = (us.rn % 5) + 1                    -- map users onto top‑5 recent closes
WHERE us.rn = 1

UNION ALL

SELECT
    NULL,
    'Aggregate Summary',
    NULL,
    SUM(us.QuestionCount)       AS TotalQuestions,
    SUM(us.AnswerCount)         AS TotalAnswers,
    SUM(us.UpVotesGiven)        AS TotalUpVotes,
    SUM(us.DownVotesGiven)      AS TotalDownVotes,
    MAX(us.LastPostDate)        AS MostRecentPost,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM UserStats us
WHERE us.rn = 1;
