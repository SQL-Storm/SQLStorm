-- {"query": "1514.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1327} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        COALESCE(t.Count, 0) AS TagCount,
        ts.Id AS ExcerptPostId,
        tw.Id AS WikiPostId
    FROM
        Tags t
        LEFT JOIN Posts ts ON t.ExcerptPostId = ts.Id
        LEFT JOIN Posts tw ON t.WikiPostId = tw.Id
    WHERE t.Id IS NOT NULL

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        pert.ThreadTagCount,
        pert.ExcerptPostId,
        pert.WikiPostId
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy pert ON t.Id = pert.Id
    WHERE t.IsRequired = 0
),
UserAnswerWindow AS (
    SELECT
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Reputation,
        u.DisplayName,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate) AS AnswerScoreRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalAnswers
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
),
ComplexPostFilters AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.ViewCount,
        q.Score,
        q.OwnerUserId,
        q.CreationDate,
        COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCounts,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        EXISTS (
            SELECT 1 FROM Votes v
            WHERE v.PostId = q.Id AND v.VoteTypeId = 2 
              AND v.CreationDate > q.CreationDate + INTERVAL '30 days'
        ) AS HasLateUpvotes,
        COALESCE(MAX(c.Score), 0) AS MaxCommentScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 14 THEN 1 ELSE 0 END), 0) AS ModeratorFlags
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.Tags, q.ViewCount, q.Score, q.OwnerUserId, q.CreationDate, q.ClosedDate
)
SELECT DISTINCT
    uq.OwnerUserId,
    COALESCE(u.DisplayName, 'Unknown') AS UserDisplayName,
    u.Reputation,
    uq.AnswerScoreRank,
    uq.TotalAnswers,
    cp.QuestionId,
    cp.Title AS QuestionTitle,
    cp.Score AS QuestionScore,
    cp.ViewCount AS QuestionViews,
    DENSE_RANK() OVER (PARTITION BY uq.OwnerUserId ORDER BY cp.Score DESC) AS UserTopScoreQuestionRank,
    cp.AnswerCounts,
    cp.IsClosed,
    cp.HasLateUpvotes,
    ROW_NUMBER() OVER (PARTITION BY cp.IsClosed ORDER BY cp.MaxCommentScore DESC) AS RowNumByClosedStatus,
    (SELECT Name FROM PostHistoryTypes pht WHERE pht.Id = (SELECT ph.PostHistoryTypeId FROM PostHistory ph WHERE ph.PostId = cp.QuestionId ORDER BY ph.CreationDate DESC LIMIT 1)) AS LatestHistoryType,
    REPLACE(REVERSE(cp.Title), ' ', '_') AS TitleReversedUnderscored,
    lg.LikelihoodCategory,
    lh.TagName,
    extract(year from u.CreationDate) AS UserOrigYear,
    extract(year from q.CreationDate) AS QuestionOrigYear,
    COUNT(DISTINCT bl.LinkTypeId) FILTER (WHERE bl.LinkTypeId = 1) AS LinkCount,
    COALESCE(blp.RelatedPostId, 0) AS LatestLinkedPostIdNULLed
FROM UserAnswerWindow uq
LEFT JOIN Users u ON uq.OwnerUserId = u.Id
LEFT JOIN ComplexPostFilters cp ON cp.OwnerUserId = uq.OwnerUserId AND uq.PostTypeId = 2 AND uq.ParentId = cp.QuestionId
LEFT JOIN PostLinks bl ON bl.PostId = cp.QuestionId
LEFT JOIN PostLinks blp ON blp.PostId = cp.QuestionId
LEFT JOIN RecursiveTagHierarchy lh ON POSITION(CONCAT('<', lh.TagName, '>') IN cp.Tags::text) > 0
LEFT JOIN (
    SELECT DISTINCT
        CASE
            WHEN u.Reputation > 10000 THEN 'Trusted'
            WHEN u.Reputation BETWEEN 2000 AND 10000 THEN 'Established'
            ELSE 'Newbie'
        END AS LikelihoodCategory,
        u.Id UserId 
    FROM Users u 
) lg ON lg.UserId = uq.OwnerUserId
LEFT JOIN Posts q ON q.Id = cp.QuestionId
WHERE (EXTRACT(DOW FROM cp.CreationDate) NOT IN (0,6) OR cp.IsClosed = 1) 
  AND (uq.AnswerScoreRank <= 5 OR cp.AnswerCounts > 3)
  AND cp.QuestionScore >= (
      SELECT AVG(p.Score)::int 
      FROM Posts p 
      WHERE p.PostTypeId = 1 AND p.CreationDate BETWEEN (CURRENT_DATE - INTERVAL '1 year') AND CURRENT_DATE
  )
UNION
SELECT 
    b.UserId,
    u.DisplayName,
    u.Reputation,
    NULL,
    NULL,
    NULL,
    'BadgeInteriorSetUnion' || RIGHT(b.Name, 2) AS QuestionTitle,
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
    0
FROM Badges b
INNER JOIN Users u ON u.Id = b.UserId
WHERE b.Name LIKE '%ing%'
ORDER BY UserDisplayName NULLS LAST, QuestionScore DESC NULLS LAST, AnswerScoreRank NULLS LAST
LIMIT 200;
