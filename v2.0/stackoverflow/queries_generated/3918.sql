-- {"query": "3918.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3237} 

/*  Benchmark query using CTEs, window functions, outer joins, correlated subqueries,
    string operations, NULL logic and set operators                                   */
WITH
    user_base AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.Location, '[unknown]')         AS Location,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            COUNT(p.Id)                               AS TotalPostCount,
            COUNT(b.Id)                               AS BadgeCount
        FROM Users u
        LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
        LEFT JOIN Badges  b ON b.UserId     = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    ),

    post_votes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Name = 'UpMod'   THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
            MAX(v.CreationDate)                                 AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ),

    recent_questions AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            p.ViewCount,
            p.CreationDate,
            p.OwnerUserId,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1            -- only questions
    ),

    tag_counts AS (
        SELECT
            t.TagName,
            COUNT(p.Id) AS PostsWithTag
        FROM Tags t
        JOIN Posts p ON p.Tags IS NOT NULL
                     AND POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
        GROUP BY t.TagName
    ),

    user_top_tag AS (
        SELECT
            ub.Id                                    AS UserId,
            tc.TagName,
            tc.PostsWithTag,
            ROW_NUMBER() OVER (PARTITION BY ub.Id ORDER BY tc.PostsWithTag DESC) AS rn
        FROM user_base ub
        JOIN Posts p   ON p.OwnerUserId = ub.Id
        JOIN Tags  t   ON POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
        JOIN tag_counts tc ON tc.TagName = t.TagName
        GROUP BY ub.Id, tc.TagName, tc.PostsWithTag
    )

SELECT
    ub.Id                               AS UserId,
    ub.DisplayName,
    ub.Reputation,
    ub.QuestionCount,
    ub.AnswerCount,
    ub.BadgeCount,
    COALESCE(pv.UpVotes,    0)          AS TotalUpVotes,
    COALESCE(pv.DownVotes, 0)          AS TotalDownVotes,
    CASE
        WHEN ub.QuestionCount = 0 THEN NULL
        ELSE ROUND( ub.AnswerCount::numeric / ub.QuestionCount, 3 )
    END                                 AS AnswersPerQuestion,
    ut.TagName                          AS TopTag,
    ut.PostsWithTag                     AS TopTagPostCount,
    rq.Title                            AS MostRecentQuestionTitle,
    rq.Score                            AS MostRecentQuestionScore,
    dl.RelatedPostId                    AS DuplicateOf,
    CASE WHEN dl.RelatedPostId IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsDuplicate
FROM user_base ub
LEFT JOIN post_votes pv
       ON pv.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = ub.Id
            ORDER BY p.CreationDate DESC
            LIMIT 1
          )
LEFT JOIN recent_questions rq
       ON rq.Id = (
            SELECT Id
            FROM recent_questions
            WHERE OwnerUserId = ub.Id AND rn = 1
          )
LEFT JOIN user_top_tag ut
       ON ut.UserId = ub.Id AND ut.rn = 1
LEFT JOIN PostLinks dl
       ON dl.PostId = rq.Id
          AND dl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
WHERE ub.Reputation > 1000
  AND ub.Location <> ''
  AND (ub.BadgeCount >= 5 OR ub.QuestionCount >= 10)
ORDER BY ub.Reputation DESC, ub.AnswerCount DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY

UNION ALL

SELECT *
FROM (
    SELECT
        NULL::int          AS UserId,
        NULL::varchar(40)  AS DisplayName,
        NULL::int          AS Reputation,
        NULL::bigint       AS QuestionCount,
        NULL::bigint       AS AnswerCount,
        NULL::int          AS BadgeCount,
        NULL::int          AS TotalUpVotes,
        NULL::int          AS TotalDownVotes,
        NULL::numeric      AS AnswersPerQuestion,
        NULL::varchar(35)  AS TopTag,
        NULL::int          AS TopTagPostCount,
        NULL::varchar(300) AS MostRecentQuestionTitle,
        NULL::int          AS MostRecentQuestionScore,
        NULL::int          AS DuplicateOf,
        NULL::varchar(3)   AS IsDuplicate
) dummy
EXCEPT
SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL;
