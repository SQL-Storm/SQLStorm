-- {"query": "1163.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1608} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(t.ExcerptPostId, -1) AS ExcerptPostId,
        COALESCE(t.WikiPostId, -1) AS WikiPostId,
        0 AS Level
    FROM
        Tags t
    WHERE
        t.Id IN (SELECT DISTINCT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))::int FROM Posts p WHERE p.PostTypeId = 1)
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        COALESCE(t2.ExcerptPostId, -1),
        COALESCE(t2.WikiPostId, -1),
        rh.Level + 1
    FROM
        Tags t2
        JOIN RecursiveTagHierarchy rh ON rh.Id <> t2.Id AND t2.Count < rh.Count AND rh.Level < 2
),
TopUsersWithBadges AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN b.Class=1 THEN 1 ELSE 0 END),0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class=2 THEN 1 ELSE 0 END),0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class=3 THEN 1 ELSE 0 END),0) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS Rnk
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        SUM(CASE WHEN b.Class=1 THEN 1 ELSE 0 END) >= 2 OR SUM(CASE WHEN b.Class=2 THEN 1 ELSE 0 END) >= 3
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreation,
        -- Correlated subquery: max score among answers of the question
        (SELECT MAX(score) FROM Posts WHERE ParentId = q.Id AND PostTypeId = 2) AS MaxAnswerScore,
        -- Window function: rank answers by score per question
        RANK() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST) AS AnswerRank
    FROM
        Posts q
        LEFT OUTER JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE
        q.PostTypeId = 1
),
PostLinkedDuplicates AS (
    SELECT
        pl.PostId,
        COUNT(pl.Id) AS DuplicateLinkCount
    FROM
        PostLinks pl
    WHERE
        pl.LinkTypeId = 3
    GROUP BY
        pl.PostId
),
RecentClosedQuestions AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastClosedDate,
        string_agg(COALESCE(crt.Name,'Unknown'), ', ') AS CloseReasons
    FROM
        PostHistory ph
        LEFT JOIN CloseReasonTypes crt ON crt.Id = ph.Comment::int
    WHERE
        ph.PostHistoryTypeId = 10
    GROUP BY
        ph.PostId
)
SELECT
    qas.QuestionId,
    TRIM(BOTH ' ' FROM REPLACE(REPLACE(REPLACE(COALESCE(qas.Title, '')), E'\n', ' '), E'\r', ' ')) AS CleanedTitle,
    qas.QuestionCreation,
    DATE_PART('year', AGE(NOW(), u.CreationDate)) AS UserAgeYears,
    u.DisplayName AS QuestionOwner,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.AnswerId,
    ansu.DisplayName AS AnswerOwner,
    qas.AnswerScore,
    qas.AnswerRank,
    qas.MaxAnswerScore,
    pl.DuplicateLinkCount,
    rcq.LastClosedDate,
    rcq.CloseReasons,
    rh.Level AS TagHierarchyLevel,
    rh.TagName,
    -- Complex predicate, handling NULL and string functions
    CASE
        WHEN u.Location IS NULL THEN 'Unknown Location'
        WHEN u.Location ILIKE '%United States%' THEN 'USA'
        WHEN u.Location ILIKE '%, %' THEN SPLIT_PART(u.Location, ',', 2)
        ELSE u.Location
    END AS NormalizedUserLocation,
    -- Conditional aggregate from correlated subquery
    (SELECT AVG(V.Score) FROM Votes V WHERE V.PostId = qas.QuestionId AND V.VoteTypeId = 2) AS AvgUpvotesOnQuestion,
    -- String expression with wildcard replacement
    CONCAT('Summary for question: "', LEFT(TRIM(qas.Title), 50), CASE WHEN LENGTH(TRIM(qas.Title)) > 50 THEN '...' ELSE '' END, '"'),
    -- NULL logic with COALESCE and CASE
    COALESCE(
        (SELECT MIN(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = qas.QuestionId AND ph.PostHistoryTypeId = 10),
        qas.QuestionCreation
    ) AS FirstCloseDateOrCreationDate
FROM
    QuestionAnswerStats qas
    LEFT JOIN Users u ON qas.OwnerUserId = u.Id
    LEFT JOIN Users ansu ON qas.AnswerOwnerUserId = ansu.Id
    LEFT JOIN TopUsersWithBadges tu ON tu.UserId = u.Id
    LEFT JOIN PostLinkedDuplicates pl ON pl.PostId = qas.QuestionId
    LEFT JOIN RecentClosedQuestions rcq ON rcq.PostId = qas.QuestionId
    LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = ANY(string_to_array(substring((SELECT Tags FROM Posts p2 WHERE p2.Id = qas.QuestionId), 2, length((SELECT Tags FROM Posts p2 WHERE p2.Id = qas.QuestionId)) - 2), '><'))
WHERE
    (qas.AnswerRank = 1 OR qas.AnswerRank IS NULL)
    AND qas.QuestionScore >= 5
    AND (tu.GoldBadges + tu.SilverBadges + tu.BronzeBadges) >= 3
ORDER BY
    qas.QuestionScore DESC,
    qas.ViewCount DESC,
    qas.AnswerCount DESC
LIMIT 50
UNION
SELECT
    qas.QuestionId,
    COALESCE(NULLIF(qas.Title, ''), 'No Title Available'),
    qas.QuestionCreation,
    0,
    'Anonymous',
    0,
    0,
    0,
    qas.QuestionScore,
    0,
    0,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'Unknown',
    NULL,
    CONCAT('No answers yet for question ID ', qas.QuestionId),
    qas.QuestionCreation
FROM
    QuestionAnswerStats qas
WHERE
    qas.AnswerCount = 0
ORDER BY
    QuestionId
LIMIT 10;
