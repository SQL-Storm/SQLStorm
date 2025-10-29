-- {"query": "3660.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2144} 

WITH RecentPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.Title,
        CASE
            WHEN p.Tags IS NOT NULL THEN regexp_split_to_array(trim(both '<>' FROM p.Tags), '><')
            ELSE NULL
        END AS TagArray
    FROM Posts p
    WHERE p.CreationDate >= now() - interval '90 days'
),
ClosedDupQuestions AS (
    SELECT
        ph.PostId               AS QuestionId,
        ph.CreationDate         AS ClosedDate,
        ph.Comment::int         AS DuplicateOfId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10                     -- Post Closed
      AND ph.Comment ~ '^\d+$'                          -- numeric close reason (duplicate)
      AND EXISTS (
          SELECT 1
          FROM PostHistory ph2
          WHERE ph2.PostId = ph.PostId
            AND ph2.PostHistoryTypeId = 10
            AND ph2.Comment::int = 101                -- duplicate reason id
      )
),
AnswersWithLag AS (
    SELECT
        a.Id                              AS AnswerId,
        a.ParentId                        AS QuestionId,
        a.OwnerUserId                     AS AnswererId,
        a.CreationDate                    AS AnswerDate,
        q.CreationDate                    AS QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 60 AS AnswerDelayMinutes,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) AS AnswerRank
    FROM Posts a
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE a.PostTypeId = 2
),
UserStats AS (
    SELECT
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(vv.VoteCount), 0)       AS TotalVotesReceived,
        AVG(CASE WHEN aw.AnswerDelayMinutes IS NOT NULL THEN aw.AnswerDelayMinutes END) AS AvgAnswerDelay,
        COUNT(DISTINCT aw.AnswerId) FILTER (WHERE aw.AnswerRank = 1) AS FirstAnswersGiven
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(*) AS VoteCount
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE v.VoteTypeId = 2               -- UpMod
        GROUP BY p.OwnerUserId
    ) vv ON vv.OwnerUserId = u.Id
    LEFT JOIN AnswersWithLag aw ON aw.AnswererId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT
        *,
        RANK() OVER (ORDER BY Reputation DESC, GoldBadges DESC, TotalVotesReceived DESC) AS RepRank
    FROM UserStats
    WHERE Reputation > 10000
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TotalVotesReceived,
    ROUND(tu.AvgAnswerDelay, 2)              AS AvgAnswerDelayMins,
    tu.FirstAnswersGiven,
    COALESCE(tu.RepRank, 0)                  AS Rank,
    COALESCE(t.TagList, '<none>')            AS RecentTags,
    CASE WHEN cdq.QuestionId IS NOT NULL THEN 'AnsweredClosedDup' ELSE 'Active' END AS StatusFlag
FROM TopUsers tu
LEFT JOIN LATERAL (
    SELECT string_agg(DISTINCT t.TagName, ', ') AS TagList
    FROM Tags t
    JOIN RecentPosts rp ON t.TagName = ANY(rp.TagArray)
    WHERE rp.OwnerUserId = tu.UserId
      AND rp.PostTypeId = 2               -- answers
    LIMIT 5
) t ON true
LEFT JOIN (
    SELECT aw.QuestionId
    FROM AnswersWithLag aw
    JOIN ClosedDupQuestions cdq ON cdq.QuestionId = aw.QuestionId
    WHERE aw.AnswererId = tu.UserId
      AND aw.AnswerRank = 1
    LIMIT 1
) cdq ON true
ORDER BY tu.Reputation DESC
FETCH FIRST 20 ROWS ONLY
UNION ALL
SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE FALSE;
