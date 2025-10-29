-- {"query": "3154.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2232} 

/* Benchmark query combining CTEs, window functions, outer joins, set operators, and complex predicates */
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.GoldCnt,0)   AS GoldBadges,
        COALESCE(b.SilverCnt,0) AS SilverBadges,
        COALESCE(b.BronzeCnt,0) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
),
TaggedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        regexp_split_to_table(p.Tags, '\><') AS Tag,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN PostHistory ph
        ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 3
    WHERE p.PostTypeId = 1
),
TagStats AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT tq.Id)                      AS QuestionCount,
        AVG(tq.Score)                              AS AvgScore,
        SUM(CASE WHEN tq.Score > 10 THEN 1 ELSE 0 END) AS HighScoreCount
    FROM Tags t
    JOIN TaggedQuestions tq ON tq.Tag = t.TagName
    GROUP BY t.TagName
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        COUNT(*) FILTER (WHERE lt.Id = 3) AS DuplicateCount,
        ARRAY_AGG(pl.RelatedPostId)        AS Duplicates
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    GROUP BY pl.PostId
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    ROUND(us.AvgPostScore::numeric,2)                       AS AvgPostScore,
    COALESCE(dl.DuplicateCount,0)                           AS DuplicateLinksSeen,
    CASE
        WHEN us.Reputation > 20000 THEN 'Legendary'
        WHEN us.Reputation > 10000 THEN 'Expert'
        WHEN us.Reputation > 5000  THEN 'Contributor'
        ELSE 'Novice'
    END                                                     AS ReputationTier,
    STRING_AGG(DISTINCT ts.TagName, ', ') FILTER (WHERE ts.TagName IS NOT NULL) AS PopularTags,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC)        AS RankByReputation,
    (SELECT COUNT(*) FROM Votes v
        WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = us.Id)
          AND v.VoteTypeId = 2)                           AS TotalUpVotes,
    (SELECT COUNT(*) FROM Votes v
        WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = us.Id)
          AND v.VoteTypeId = 3)                           AS TotalDownVotes
FROM UserStats us
LEFT JOIN DuplicateLinks dl      ON dl.PostId = us.Id                     -- outer join, many mismatches
LEFT JOIN TagStats ts           ON ts.TagName = ANY (SELECT regexp_split_to_array(us.DisplayName, '\s+')) -- arbitrary join for complexity
GROUP BY
    us.Id, us.DisplayName, us.Reputation,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    us.QuestionCount, us.AnswerCount, us.AvgPostScore,
    dl.DuplicateCount
HAVING COUNT(*) FILTER (WHERE us.Reputation IS NOT NULL) > 0
ORDER BY us.Reputation DESC
LIMIT 100

UNION ALL

SELECT
    NULL,
    'Aggregated Totals',
    SUM(us.Reputation),
    SUM(us.GoldBadges),
    SUM(us.SilverBadges),
    SUM(us.BronzeBadges),
    SUM(us.QuestionCount),
    SUM(us.AnswerCount),
    ROUND(AVG(us.AvgPostScore)::numeric,2),
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM UserStats us;
