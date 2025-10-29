-- {"query": "3589.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2229} 

/*-----------------------------------------------------------------
  Benchmark query: combines CTEs, window functions, outer joins,
  correlated subqueries, complex predicates, string ops and NULL
  handling, ending with a UNION ALL set operator.
-----------------------------------------------------------------*/
WITH 
/* 1. Base statistics per user */
UserBase AS (
    SELECT 
        u.Id                               AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate                     AS UserSince,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)           AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)           AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)           AS BronzeBadges,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)      AS TotalAnswers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)     AS AvgAnswerScore,
        MAX(p.CreationDate)               AS LastAnswerDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),

/* 2. Recent voting activity (last 30 days) */
RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(*)                               AS VotesLast30d,
        MAX(v.CreationDate)                    AS LastVoteDate,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotesLast30d,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotesLast30d
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    GROUP BY v.UserId
),

/* 3. Users with at least one answer that was edited after creation
     (demonstrates a correlated subquery) */
EditedAnswers AS (
    SELECT 
        a.OwnerUserId                         AS UserId,
        COUNT(*)                              AS EditedAnswerCount
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND EXISTS (
            SELECT 1
            FROM PostHistory ph
            WHERE ph.PostId = a.Id
              AND ph.PostHistoryTypeId IN (4,5,6)   -- edit title/body/tags
              AND ph.CreationDate > a.CreationDate
        )
    GROUP BY a.OwnerUserId
),

/* 4. Tag popularity for each user (string aggregation) */
UserTagInfo AS (
    SELECT 
        p.OwnerUserId                         AS UserId,
        STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM t.TagName), ', ') 
                                             AS TagList,
        COUNT(DISTINCT t.Id)                  AS DistinctTagCount
    FROM Posts p
    JOIN UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag(tagname) ON TRUE
    JOIN Tags t ON t.TagName = tag.tagname
    WHERE p.PostTypeId = 1                 -- only questions carry tags
    GROUP BY p.OwnerUserId
),

/* 5. Rank users by a weighted score */
UserRanking AS (
    SELECT 
        ub.*,
        COALESCE(rv.VotesLast30d,0)               AS VotesLast30d,
        COALESCE(ea.EditedAnswerCount,0)          AS EditedAnswers,
        COALESCE(uti.DistinctTagCount,0)          AS TagDiversity,
        /* weighted composite score */
        (ub.Reputation * 0.4
         + ub.GoldBadges * 100
         + ub.TotalAnswers * 5
         + COALESCE(rv.UpVotesLast30d,0) * 2
         - COALESCE(rv.DownVotesLast30d,0) * 3
         + ub.AvgAnswerScore * 10
         + COALESCE(ea.EditedAnswerCount,0) * 7
         + COALESCE(uti.DistinctTagCount,0) * 12) AS CompositeScore,
        ROW_NUMBER() OVER (ORDER BY 
            (ub.Reputation * 0.4
             + ub.GoldBadges * 100
             + ub.TotalAnswers * 5
             + COALESCE(rv.UpVotesLast30d,0) * 2
             - COALESCE(rv.DownVotesLast30d,0) * 3
             + ub.AvgAnswerScore * 10
             + COALESCE(ea.EditedAnswerCount,0) * 7
             + COALESCE(uti.DistinctTagCount,0) * 12) DESC) AS Rank
    FROM UserBase      ub
    LEFT JOIN RecentVotes    rv ON rv.UserId = ub.UserId
    LEFT JOIN EditedAnswers  ea ON ea.UserId = ub.UserId
    LEFT JOIN UserTagInfo    uti ON uti.UserId = ub.UserId
)

SELECT 
    ur.Rank,
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.TotalAnswers,
    ROUND(ur.AvgAnswerScore,2)          AS AvgAnswerScore,
    ur.VotesLast30d,
    TO_CHAR(ur.LastVoteDate,'YYYY-MM-DD') AS LastVoteDate,
    ur.EditedAnswers,
    COALESCE(uti.TagList,'<none>')      AS TagsUsed,
    /* summary string with NULL handling */
    CASE 
        WHEN ur.TotalAnswers = 0 THEN 'No answers yet'
        ELSE CONCAT(
                ur.GoldBadges, ' gold, ',
                ur.SilverBadges, ' silver, ',
                ur.BronzeBadges, ' bronze; ',
                ur.TotalAnswers, ' answers (avg ', 
                ROUND(ur.AvgAnswerScore,2), ')'
             )
    END                                 AS Summary,
    ur.CompositeScore
FROM UserRanking ur
LEFT JOIN UserTagInfo uti ON uti.UserId = ur.UserId
WHERE ur.Rank <= 50

UNION ALL

/* Footer row – demonstrates set operator and constant expressions */
SELECT 
    NULL      AS Rank,
    NULL      AS UserId,
    '---'     AS DisplayName,
    NULL      AS Reputation,
    NULL      AS GoldBadges,
    NULL      AS SilverBadges,
    NULL      AS BronzeBadges,
    NULL      AS TotalAnswers,
    NULL      AS AvgAnswerScore,
    NULL      AS VotesLast30d,
    NULL      AS LastVoteDate,
    NULL      AS EditedAnswers,
    NULL      AS TagsUsed,
    'End of Top‑50 Users' AS Summary,
    NULL      AS CompositeScore
ORDER BY Rank ASC NULLS LAST;
