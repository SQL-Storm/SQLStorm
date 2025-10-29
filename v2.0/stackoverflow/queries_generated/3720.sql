-- {"query": "3720.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1861} 

WITH
    ParsedTags AS (
        SELECT
            p.Id AS PostId,
            UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1                -- only questions
    ),
    TagStats AS (
        SELECT
            pt.Tag,
            COUNT(*)                                            AS QuestionCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)    AS AvgScore,
            SUM(p.ViewCount)                                   AS TotalViews,
            COUNT(DISTINCT p.OwnerUserId)                       AS DistinctAuthors
        FROM ParsedTags pt
        JOIN Posts p ON p.Id = pt.PostId
        GROUP BY pt.Tag
    ),
    UserActivity AS (
        SELECT
            u.Id                                   AS UserId,
            u.Reputation,
            COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionsAsked,
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswersGiven,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
        FROM Users u
    ),
    TopTagAuthors AS (
        SELECT
            ts.Tag,
            ua.UserId,
            ua.Reputation,
            ROW_NUMBER() OVER (PARTITION BY ts.Tag ORDER BY ua.Reputation DESC) AS rn
        FROM TagStats ts
        JOIN ParsedTags pt ON pt.Tag = ts.Tag
        JOIN Posts p ON p.Id = pt.PostId
        JOIN UserActivity ua ON ua.UserId = p.OwnerUserId
        WHERE p.OwnerUserId IS NOT NULL
    )
SELECT
    ts.Tag,
    ts.QuestionCount,
    ts.AvgScore,
    ts.TotalViews,
    ts.DistinctAuthors,
    COALESCE(tta.UserId, -1)                         AS TopAuthorUserId,
    COALESCE(tta.Reputation, 0)                      AS TopAuthorReputation,
    CASE
        WHEN ts.TotalViews > 100000 THEN 'Hot'
        WHEN ts.QuestionCount > 500   THEN 'Popular'
        ELSE 'Normal'
    END                                             AS PopularityTier,
    (SELECT COUNT(*)
       FROM Posts p2
       WHERE p2.PostTypeId = 1
         AND p2.CreationDate > CURRENT_DATE - INTERVAL '30 days'
         AND EXISTS (SELECT 1
                       FROM ParsedTags pt2
                       WHERE pt2.PostId = p2.Id
                         AND pt2.Tag = ts.Tag)
    )                                               AS Recent30DayQuestions,
    (SELECT COUNT(*)
       FROM Votes v
       JOIN Posts p3 ON p3.Id = v.PostId
       WHERE v.VoteTypeId = 2                     -- upvotes
         AND p3.PostTypeId = 1
         AND EXISTS (SELECT 1
                       FROM ParsedTags pt3
                       WHERE pt3.PostId = p3.Id
                         AND pt3.Tag = ts.Tag)
    )                                               AS TotalUpVotesForTag
FROM TagStats ts
LEFT JOIN (
    SELECT Tag, UserId, Reputation
    FROM TopTagAuthors
    WHERE rn = 1
) tta ON tta.Tag = ts.Tag
WHERE ts.QuestionCount > 10
ORDER BY ts.TotalViews DESC
LIMIT 100

UNION ALL

SELECT
    'TOTAL'                                     AS Tag,
    SUM(QuestionCount),
    AVG(AvgScore),
    SUM(TotalViews),
    SUM(DistinctAuthors),
    NULL,
    NULL,
    'Aggregate',
    NULL,
    NULL
FROM TagStats
HAVING COUNT(*) > 0;
